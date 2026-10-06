import test from 'node:test';
import assert from 'node:assert/strict';
import { execFile, spawn } from 'node:child_process';
import { promisify } from 'node:util';
import { mkdtemp, mkdir, readFile, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { chromium } from 'playwright';
import { starterConfig } from '../lib/config-v2.mjs';

const packageRoot = new URL('../..', import.meta.url).pathname;
const token = 'configuration-round-trip-token';
const execFileAsync = promisify(execFile);

async function startServer(configRoot, stateRoot, extraEnv = {}) {
  const skhdFile = join(stateRoot, 'test.skhdrc');
  const child = spawn(process.execPath, [
    join(packageRoot, 'configurator/server.mjs'),
    `--package-root=${packageRoot}`,
    `--config-root=${configRoot}`,
    `--state-root=${stateRoot}`,
    `--skhd-file=${skhdFile}`,
    `--token=${token}`,
    '--port=0',
    '--no-open'
  ], { stdio: ['ignore', 'pipe', 'pipe'], env: { ...process.env, ...extraEnv } });

  const url = await new Promise((resolve, reject) => {
    let output = '';
    const timer = setTimeout(() => reject(new Error(`server did not start: ${output}`)), 5000);
    child.once('error', reject);
    child.stderr.on('data', (chunk) => { output += chunk; });
    child.stdout.on('data', (chunk) => {
      output += chunk;
      const match = output.match(/SPACEWRIGHT_CONFIGURATOR_URL=(http:\/\/[^\s]+)/);
      if (match) {
        clearTimeout(timer);
        resolve(match[1]);
      }
    });
  });
  return { child, url };
}

async function stopServer(child) {
  if (child.exitCode !== null) return;
  child.kill('SIGTERM');
  await new Promise((resolve) => child.once('exit', resolve));
}

async function readJson(path) {
  return JSON.parse(await readFile(path, 'utf8'));
}

async function writeJson(path, value) {
  await writeFile(path, `${JSON.stringify(value, null, 2)}\n`, { mode: 0o600 });
}

test('Configuration GUI round-trips the authoritative config file', { timeout: 60_000 }, async (context) => {
  const root = await mkdtemp(join(tmpdir(), 'spacewright-config-round-trip-'));
  const configRoot = join(root, 'config');
  const stateRoot = join(root, 'state');
  const configFile = join(configRoot, 'config.v2.json');
  const fakeBin = join(root, 'bin');
  const original = starterConfig();
  original.displayRoles.primary.name = 'Authoritative primary display';
  original.apps.hermes = { name: 'Hermes', match: { appNames: ['Hermes'] } };
  original.aiProviders.hermes = { name: 'Hermes', app: 'hermes' };
  original.apps.runtime_only = { name: 'Runtime Only', match: { appNames: ['Runtime Only'] } };
  original.workspaces.coding.variants.solo.runtime = { runner: 'generic_layout', windows: [
    { role: 'editor', app_key: 'code', required: true },
    { role: 'assistant', app_key: 'chatgpt', required: false },
    { role: 'runtime_helper', app_key: 'runtime_only', required: false }
  ] };
  await mkdir(configRoot, { recursive: true });
  await mkdir(stateRoot, { recursive: true });
  await mkdir(fakeBin, { recursive: true });
  await writeJson(configFile, original);
  await writeJson(join(stateRoot, 'machine.json'), { version: 1, displayBindings: { primary: 'DISPLAY-PRIMARY' } });
  await writeFile(join(fakeBin, 'yabai'), `#!/bin/sh
case "$3" in
  --displays) printf '%s\n' '[{"index":1,"uuid":"DISPLAY-PRIMARY","label":"Built-in","frame":{"x":0,"y":0,"w":1200,"h":900},"is-built-in":true,"has-focus":true,"spaces":[1]}]' ;;
  --spaces) printf '%s\n' '[{"index":1,"uuid":"SPACE-1","display":1,"label":"coding_wide","type":"float","has-focus":true}]' ;;
  --windows) printf '%s\n' '[{"id":10,"pid":100,"app":"Code","title":"Project","role":"AXWindow","subrole":"AXStandardWindow","display":1,"space":1,"frame":{"x":400,"y":0,"w":800,"h":900},"can-move":true,"can-resize":true,"is-visible":true},{"id":11,"pid":101,"app":"ChatGPT","title":"Assistant","role":"AXWindow","subrole":"AXStandardWindow","display":1,"space":1,"frame":{"x":0,"y":0,"w":400,"h":900},"can-move":true,"can-resize":true,"is-visible":true}]' ;;
  *) exit 2 ;;
esac
`, { mode: 0o755 });
  const serverEnv = { PATH: `${fakeBin}:${process.env.PATH}` };

  let service = await startServer(configRoot, stateRoot, serverEnv);
  const browser = await chromium.launch();
  const page = await browser.newPage({ viewport: { width: 1440, height: 1000 } });
  context.after(async () => {
    await browser.close();
    await stopServer(service.child);
    await rm(root, { recursive: true, force: true });
  });

  const backendBefore = await readJson(configFile);
  assert.equal(backendBefore.displayRoles.primary.name, 'Authoritative primary display');

  await page.goto(service.url);
  await page.getByRole('heading', { name: /1 displays · 1 Spaces · 2 windows/ }).waitFor();
  const wakeDryRun = await execFileAsync(process.execPath, [join(packageRoot, 'configurator/state-cli.mjs'), 'event', 'wake', `--package-root=${packageRoot}`, `--config-root=${configRoot}`, `--state-root=${stateRoot}`, '--dry-run'], { env: { ...process.env, ...serverEnv } });
  assert.match(wakeDryRun.stdout, /dry_run=event/);
  await page.getByRole('button', { name: 'Compare workspace' }).click();
  await page.getByText(/Plan [a-f0-9]+ is/).waitFor();
  await page.locator('#nav [data-view="ai"]').click();
  await page.getByRole('heading', { name: 'One AI choice, shared across every shape' }).waitFor();
  await page.locator('#ai-route-workspace').selectOption('coding');
  await page.locator('#ai-route-role').selectOption('assistant');
  await page.locator('#ai-route-provider').selectOption('chatgpt');
  await page.getByRole('button', { name: 'Add route' }).click();
  await page.locator('[data-ai-override="coding:wide"]').selectOption('hermes');
  assert.equal(await page.locator('[data-ai-default="coding"]').inputValue(), 'chatgpt');
  assert.equal(await page.locator('[data-ai-override="coding:wide"]').inputValue(), 'hermes');
  assert.match(await page.locator('.ai-route-row').innerText(), /solo[\s\S]*ChatGPT[\s\S]*wide[\s\S]*Hermes/i);
  assert.equal(Object.keys((await readJson(configFile)).aiRouting.assignments).length, 0);
  await page.setViewportSize({ width: 780, height: 1000 });
  assert.equal(await page.evaluate(() => document.documentElement.scrollWidth <= document.documentElement.clientWidth), true);
  await page.setViewportSize({ width: 1440, height: 1000 });
  await page.locator('#nav [data-view="current"]').click();
  await page.locator('#capture-id').fill('captured_test');
  await page.locator('#capture-name').fill('Captured Test');
  await page.getByRole('button', { name: 'Capture into editor' }).click();
  await page.locator('#workspace-id').waitFor();
  assert.equal(await page.locator('#workspace-id').inputValue(), 'captured_test');
  assert.equal(Object.hasOwn(await readJson(configFile).then((value) => value.workspaces), 'captured_test'), false);
  await page.reload();
  await page.getByRole('button', { name: /Profiles & Rules/i }).click();
  await page.getByRole('button', { name: 'Add Profile' }).click();
  await page.locator('[data-profile-display="research"]').selectOption('wide_left');
  await page.locator('[data-profile-focus="research"]').selectOption('coding');
  await page.locator('#topology-samples').fill('4');
  await page.locator('#topology-samples').press('Enter');
  await page.getByRole('button', { name: 'Dry run' }).click();
  await page.getByText('Dry run · no desktop changes').waitFor();
  assert.equal(Object.hasOwn(await readJson(configFile).then((value) => value.profiles || {}), 'research'), false);
  await page.reload();
  await page.locator('#status').filter({ hasNotText: 'Loading configuration' }).waitFor();
  await page.locator('#nav [data-view="workspaces"]').click();
  await page.getByRole('heading', { name: 'Workspaces by display' }).waitFor();
  await page.getByRole('tab', { name: 'Layout', exact: true }).click();
  await page.getByRole('button', { name: 'Edit freely' }).evaluate((button) => button.click());
  assert.equal(await page.locator('.canvas-window').count(), 2);
  const width = page.locator('[data-geometry="w:editor"]');
  await width.fill('5');
  await width.press('Enter');
  assert.match(await page.locator('.canvas-window[data-role="editor"]').getAttribute('style'), /--w:5/);
  await page.getByRole('tab', { name: 'Apps & Shortcuts' }).evaluate((button) => button.click());
  await page.getByRole('button', { name: '+ Add app window' }).click();
  await page.getByRole('tab', { name: 'Layout', exact: true }).evaluate((button) => button.click());
  assert.equal(await page.locator('.canvas-window').count(), 3);
  await page.getByRole('tab', { name: 'Window Matching / Advanced' }).evaluate((button) => button.click());
  await page.locator('.window-card').filter({ hasText: 'window_1' }).locator('summary').click();
  await page.locator('[data-delete-window="window_1"]').click();
  await page.locator('dialog.modal-dialog').getByRole('button', { name: 'Remove Window' }).click();
  await page.locator('dialog.modal-dialog').waitFor({ state: 'detached' });
  await page.getByRole('tab', { name: 'Layout', exact: true }).click();
  assert.equal(await page.locator('.canvas-window').count(), 2);
  const unlabeledControls = await page.evaluate(() => [...document.querySelectorAll('input:not([type="hidden"]):not([hidden]), select')].filter((control) => {
    if (control.getAttribute('aria-label')) return false;
    if (control.id && document.querySelector(`label[for="${CSS.escape(control.id)}"]`)) return false;
    return !control.closest('label');
  }).map((control) => control.outerHTML));
  assert.deepEqual(unlabeledControls, []);
  const overflowing = await page.evaluate(() => [...document.querySelectorAll('*')]
    .filter((element) => element.getBoundingClientRect().right > document.documentElement.clientWidth + 1)
    .map((element) => `${element.tagName}.${element.className}:${element.getBoundingClientRect().left}/${element.getBoundingClientRect().right}/${element.parentElement.getBoundingClientRect().width}`));
  assert.deepEqual(overflowing, []);
  await page.setViewportSize({ width: 780, height: 1000 });
  assert.equal(await page.evaluate(() => document.documentElement.scrollWidth <= document.documentElement.clientWidth), true);
  await page.setViewportSize({ width: 1440, height: 1000 });
  await page.getByRole('button', { name: 'Rename ID' }).first().click();
  await page.locator('dialog.modal-dialog input').fill('coding_renamed');
  await page.locator('dialog.modal-dialog').getByRole('button', { name: 'Apply' }).click();
  await page.locator('dialog.modal-dialog').waitFor({ state: 'detached' });
  await page.locator('#workspace-id').waitFor();
  assert.equal(await page.locator('#workspace-id').inputValue(), 'coding_renamed');
  await page.reload();
  await page.locator('#status').filter({ hasNotText: 'Loading configuration' }).waitFor();
  await page.locator('#nav [data-view="apps"]').click();
  const runtimeOnly = page.locator('.app-list-row').filter({ hasText: 'Runtime Only' });
  await runtimeOnly.locator('summary').click();
  await runtimeOnly.getByRole('button', { name: 'Delete App' }).click();
  await assert.doesNotReject(() => page.getByRole('status').filter({ hasText: /solo runtime · runtime_helper/ }).waitFor());
  assert.equal(await page.locator('[data-delete-app="runtime_only"]').count(), 1);
  await page.locator('#nav [data-view="displays"]').click();
  const primaryName = page.locator('[data-display-name="primary"]');
  await assert.doesNotReject(() => primaryName.waitFor());
  assert.equal(await primaryName.inputValue(), backendBefore.displayRoles.primary.name);

  const guiValue = 'GUI round-trip display';
  await primaryName.fill(guiValue);
  await page.getByRole('button', { name: 'Undo configuration change' }).click();
  assert.equal(await page.locator('[data-display-name="primary"]').inputValue(), backendBefore.displayRoles.primary.name);
  await page.getByRole('button', { name: 'Redo configuration change' }).click();
  assert.equal(await page.locator('[data-display-name="primary"]').inputValue(), guiValue);
  await page.getByRole('button', { name: 'Save configuration' }).click();
  await page.locator('dialog.modal-dialog').getByRole('button', { name: 'Save Changes' }).click();
  await page.getByText(`Saved and read-back verified: ${configFile}`).waitFor();
  assert.equal((await readJson(configFile)).displayRoles.primary.name, guiValue);

  await page.reload();
  await page.locator('#status').filter({ hasNotText: 'Loading configuration' }).waitFor();
  await page.locator('#nav [data-view="displays"]').click();
  assert.equal(await page.locator('[data-display-name="primary"]').inputValue(), guiValue);

  const externalValue = 'Backend-updated display';
  const externallyChanged = await readJson(configFile);
  externallyChanged.displayRoles.primary.name = externalValue;
  await writeJson(configFile, externallyChanged);
  await page.reload();
  await page.getByRole('button', { name: /Displays/ }).click();
  assert.equal(await page.locator('[data-display-name="primary"]').inputValue(), externalValue);

  await stopServer(service.child);
  service = await startServer(configRoot, stateRoot, serverEnv);
  await page.goto(service.url);
  await page.getByRole('button', { name: /Displays/ }).click();
  assert.equal(await page.locator('[data-display-name="primary"]').inputValue(), externalValue);

  await writeJson(configFile, original);
  await page.reload();
  await page.getByRole('button', { name: /Displays/ }).click();
  assert.equal(await page.locator('[data-display-name="primary"]').inputValue(), original.displayRoles.primary.name);
  assert.deepEqual(await readJson(configFile), original);
});
