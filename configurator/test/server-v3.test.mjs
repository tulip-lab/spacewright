import test from 'node:test';
import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { chmod, mkdir, mkdtemp, readFile, rm, writeFile } from 'node:fs/promises';
import { existsSync } from 'node:fs';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import { chromium } from 'playwright';
import { starterV3 } from '../lib/config-v3.mjs';

const packageRoot = new URL('../..', import.meta.url).pathname;
const systemChrome = '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';

async function startServer(configRoot, stateRoot, fakeBin) {
  const token = 'v3-integration-token';
  const child = spawn(process.execPath, [
    join(packageRoot, 'configurator/server.mjs'),
    `--package-root=${packageRoot}`,
    `--config-root=${configRoot}`,
    `--state-root=${stateRoot}`,
    `--token=${token}`,
    '--port=0',
    '--no-open'
  ], { env: { ...process.env, PATH: `${fakeBin}:${process.env.PATH}` }, stdio: ['ignore', 'pipe', 'pipe'] });
  const url = await new Promise((resolve, reject) => {
    let output = '';
    const timer = setTimeout(() => reject(new Error(`server did not start: ${output}`)), 5000);
    child.once('error', reject);
    child.stderr.on('data', (chunk) => { output += chunk; });
    child.stdout.on('data', (chunk) => {
      output += chunk;
      const match = output.match(/SPACEWRIGHT_CONFIGURATOR_URL=(http:\/\/[^?\s]+)/);
      if (match) { clearTimeout(timer); resolve(match[1]); }
    });
  });
  return { child, token, url };
}

async function json(url, path, token, options = {}) {
  const response = await fetch(new URL(path.slice(1), url), { ...options, headers: { 'content-type': 'application/json', ...(token ? { 'x-spacewright-token': token } : {}), ...(options.headers || {}) } });
  return { status: response.status, body: await response.json() };
}

test('v3 server confirms a Mac mini display setup and saves a digest-bound runtime', async (context) => {
  const root = await mkdtemp(join(tmpdir(), 'spacewright-server-v3-'));
  const configRoot = join(root, 'config');
  const stateRoot = join(root, 'state');
  const fakeBin = join(root, 'fake-bin');
  await Promise.all([mkdir(configRoot), mkdir(stateRoot), mkdir(fakeBin)]);
  const config = starterV3();
  await writeFile(join(configRoot, 'config.v3.json'), `${JSON.stringify(config, null, 2)}\n`);
  await writeFile(join(fakeBin, 'sysctl'), '#!/bin/sh\nprintf "%s\\n" "Macmini9,1"\n');
  await writeFile(join(fakeBin, 'yabai'), `#!/bin/sh
case "$3" in
  --displays) printf '%s\n' '[{"index":1,"uuid":"DISPLAY-TALL-1234","frame":{"x":0,"y":0,"w":1200,"h":1920},"is-built-in":false,"spaces":[1]}]' ;;
  --spaces) printf '%s\n' '[{"index":1,"uuid":"SPACE-CODING","display":1,"label":"coding_tall","type":"float"}]' ;;
  --windows) printf '%s\n' '[{"id":10,"app":"Code","display":1,"space":1,"frame":{"x":0,"y":0,"w":1200,"h":1920},"can-move":true,"can-resize":true,"is-visible":true}]' ;;
esac
`);
  await Promise.all([chmod(join(fakeBin, 'sysctl'), 0o755), chmod(join(fakeBin, 'yabai'), 0o755)]);
  const { child, token, url } = await startServer(configRoot, stateRoot, fakeBin);
  context.after(async () => { child.kill('SIGTERM'); await rm(root, { recursive: true, force: true }); });

  const document = await json(url, '/api/v3/config');
  assert.equal(document.status, 200);
  assert.equal(document.body.source, 'v3');
  const detected = await json(url, '/api/v3/setup');
  assert.equal(detected.status, 200);
  assert.equal(detected.body.hardwareSelection.id, 'mac_mini', JSON.stringify(detected.body));
  assert.deepEqual(detected.body.setupCandidates, ['single_tall'], JSON.stringify(detected.body));
  assert.equal(detected.body.ready, false);

  const confirmed = await json(url, '/api/v3/setup/confirm', token, {
    method: 'POST',
    body: JSON.stringify({ config, hardwareProfile: 'mac_mini', setup: 'single_tall' })
  });
  assert.equal(confirmed.status, 200, JSON.stringify(confirmed.body));
  assert.equal(confirmed.body.machine.displayBindings.tall, 'DISPLAY-TALL-1234');
  assert.equal(confirmed.body.machine.topologySelections['external:tall'], 'single_tall');

  const saved = await json(url, '/api/v3/save', token, {
    method: 'POST',
    body: JSON.stringify({ config, baseRevision: document.body.revision })
  });
  assert.equal(saved.status, 200, JSON.stringify(saved.body));
  assert.equal(saved.body.verified, true);
  const runtime = JSON.parse(await readFile(join(configRoot, 'generated', 'runtime.json'), 'utf8'));
  assert.equal(runtime.source_version, 3);
  assert.equal(runtime.active_hardware_profile, 'mac_mini');
  assert.equal(runtime.active_setup, 'single_tall');
  assert.match(runtime.generated.source_sha256, /^[a-f0-9]{64}$/);

  const activated = await json(url, '/api/v3/setup/activate', token, { method: 'POST', body: '{}' });
  assert.equal(activated.status, 200);
  assert.equal(activated.body.compatibilityMode, 'tall');

  const preview = await json(url, '/api/preview', token, {
    method: 'POST',
    body: JSON.stringify({ kind: 'workspace', target: 'coding' })
  });
  assert.equal(preview.status, 200, JSON.stringify(preview.body));
  assert.equal(preview.body.resolution.hardwareProfileId, 'mac_mini');
  assert.equal(preview.body.resolution.setupId, 'single_tall');
  assert.equal(preview.body.plan.target.mode, 'tall');

  const browser = await chromium.launch({ headless: true, ...(existsSync(systemChrome) ? { executablePath: systemChrome } : {}) });
  context.after(() => browser.close());
  const page = await browser.newPage({ viewport: { width: 1440, height: 1000 } });
  const pageErrors = [];
  page.on('pageerror', (error) => pageErrors.push(error.message));
  const pageUrl = new URL(url);
  pageUrl.searchParams.set('token', token);
  pageUrl.searchParams.set('view', 'hardware');
  await page.goto(pageUrl.href);
  try {
    await page.getByRole('heading', { name: 'Mac → setup → workspace configuration' }).waitFor({ timeout: 20_000 });
  } catch (error) {
    throw new Error(`${error.message}\npage=${(await page.content()).slice(0, 2000)}\npageErrors=${pageErrors.join('; ')}`);
  }
  assert.match(await page.locator('.v3-detection').innerText(), /Macmini9,1 · mac_mini[\s\S]*confirmed as single_tall/);
  assert.equal(await page.locator('[data-v3-setup="single_tall"]').getAttribute('class'), 'active');
  assert.equal(await page.locator('[data-v3-assignment="coding"]').inputValue(), 'tall');
  assert.equal(await page.locator('#v3-configuration').inputValue(), 'tall');
  await page.getByRole('button', { name: 'Edit exact grid' }).click();
  assert.equal(await page.locator('.canvas-window').count(), 1);
  const unlabeledControls = await page.evaluate(() => [...document.querySelectorAll('input:not([type="hidden"]):not([hidden]), select')].filter((control) => {
    if (control.getAttribute('aria-label')) return false;
    if (control.id && document.querySelector(`label[for="${CSS.escape(control.id)}"]`)) return false;
    return !control.closest('label');
  }).map((control) => control.outerHTML));
  assert.deepEqual(unlabeledControls, []);
  await page.setViewportSize({ width: 780, height: 1000 });
  assert.equal(await page.evaluate(() => document.documentElement.scrollWidth <= document.documentElement.clientWidth), true);
  assert.deepEqual(pageErrors, []);

  const candidate = structuredClone(config);
  candidate.hardwareProfiles.mac_mini.setups.single_tall_custom = structuredClone(candidate.hardwareProfiles.mac_mini.setups.single_tall);
  candidate.hardwareProfiles.mac_mini.setups.single_tall_custom.name = 'Single tall custom';
  const candidateConfirmation = await json(url, '/api/v3/setup/confirm', token, {
    method: 'POST',
    body: JSON.stringify({ config: candidate, hardwareProfile: 'mac_mini', setup: 'single_tall_custom' })
  });
  assert.equal(candidateConfirmation.status, 200, JSON.stringify(candidateConfirmation.body));
  assert.equal(candidateConfirmation.body.setupState.ready, true);
  assert.equal(candidateConfirmation.body.setupState.confirmedSetup, 'single_tall_custom');
  const candidateSave = await json(url, '/api/v3/save', token, {
    method: 'POST',
    body: JSON.stringify({ config: candidate, baseRevision: saved.body.revision })
  });
  assert.equal(candidateSave.status, 200, JSON.stringify(candidateSave.body));
});
