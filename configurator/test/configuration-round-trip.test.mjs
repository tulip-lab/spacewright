import test from 'node:test';
import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { mkdtemp, mkdir, readFile, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { chromium } from 'playwright';
import { starterConfig } from '../lib/config-v2.mjs';

const packageRoot = new URL('../..', import.meta.url).pathname;
const token = 'configuration-round-trip-token';

async function startServer(configRoot, stateRoot) {
  const child = spawn(process.execPath, [
    join(packageRoot, 'configurator/server.mjs'),
    `--package-root=${packageRoot}`,
    `--config-root=${configRoot}`,
    `--state-root=${stateRoot}`,
    `--token=${token}`,
    '--port=0',
    '--no-open'
  ], { stdio: ['ignore', 'pipe', 'pipe'] });

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

test('Configuration GUI round-trips the authoritative config file', { timeout: 30_000 }, async (context) => {
  const root = await mkdtemp(join(tmpdir(), 'spacewright-config-round-trip-'));
  const configRoot = join(root, 'config');
  const stateRoot = join(root, 'state');
  const configFile = join(configRoot, 'config.v2.json');
  const original = starterConfig();
  original.displayRoles.primary.name = 'Authoritative primary display';
  await mkdir(configRoot, { recursive: true });
  await writeJson(configFile, original);

  let service = await startServer(configRoot, stateRoot);
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
  await page.getByRole('button', { name: /Workspaces/ }).click();
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
  page.once('dialog', (dialog) => dialog.accept('coding_renamed'));
  await page.getByRole('button', { name: 'Rename ID' }).first().click();
  await page.locator('#workspace-id').waitFor();
  assert.equal(await page.locator('#workspace-id').inputValue(), 'coding_renamed');
  await page.reload();
  await page.getByRole('button', { name: /Displays/ }).click();
  const primaryName = page.locator('[data-display-name="primary"]');
  await assert.doesNotReject(() => primaryName.waitFor());
  assert.equal(await primaryName.inputValue(), backendBefore.displayRoles.primary.name);

  const guiValue = 'GUI round-trip display';
  await primaryName.fill(guiValue);
  await page.getByRole('button', { name: 'Save configuration' }).click();
  await page.getByText(`Saved ${configFile}`).waitFor();
  assert.equal((await readJson(configFile)).displayRoles.primary.name, guiValue);

  await page.reload();
  await page.getByRole('button', { name: /Displays/ }).click();
  assert.equal(await page.locator('[data-display-name="primary"]').inputValue(), guiValue);

  const externalValue = 'Backend-updated display';
  const externallyChanged = await readJson(configFile);
  externallyChanged.displayRoles.primary.name = externalValue;
  await writeJson(configFile, externallyChanged);
  await page.reload();
  await page.getByRole('button', { name: /Displays/ }).click();
  assert.equal(await page.locator('[data-display-name="primary"]').inputValue(), externalValue);

  await stopServer(service.child);
  service = await startServer(configRoot, stateRoot);
  await page.goto(service.url);
  await page.getByRole('button', { name: /Displays/ }).click();
  assert.equal(await page.locator('[data-display-name="primary"]').inputValue(), externalValue);

  await writeJson(configFile, original);
  await page.reload();
  await page.getByRole('button', { name: /Displays/ }).click();
  assert.equal(await page.locator('[data-display-name="primary"]').inputValue(), original.displayRoles.primary.name);
  assert.deepEqual(await readJson(configFile), original);
});
