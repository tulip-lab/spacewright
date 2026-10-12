import test from 'node:test';
import assert from 'node:assert/strict';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { mkdtemp, mkdir, readFile, rm, writeFile } from 'node:fs/promises';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import { starterV3 } from '../lib/config-v3.mjs';

const execFileAsync = promisify(execFile);
const cli = new URL('../setup-cli.mjs', import.meta.url).pathname;

test('setup CLI detects, confirms, persists, and activates a Mac mini tall setup', async () => {
  const root = await mkdtemp(join(tmpdir(), 'spacewright-setup-cli-'));
  const configRoot = join(root, 'config');
  const stateRoot = join(root, 'state');
  const snapshot = join(root, 'displays.json');
  await Promise.all([mkdir(configRoot), mkdir(stateRoot)]);
  await writeFile(join(configRoot, 'config.v3.json'), `${JSON.stringify(starterV3(), null, 2)}\n`);
  await writeFile(snapshot, JSON.stringify({ unavailable: false, displays: [{ index: 1, uuid: 'DISPLAY-TALL-1234', frame: { x: 0, y: 0, w: 1200, h: 1920 }, 'is-built-in': false }] }));
  const common = [`--config-root=${configRoot}`, `--state-root=${stateRoot}`, `--snapshot=${snapshot}`, '--model=Macmini9,1'];
  try {
    const detected = JSON.parse((await execFileAsync(process.execPath, [cli, 'detect', ...common])).stdout);
    assert.equal(detected.hardwareSelection.id, 'mac_mini');
    assert.deepEqual(detected.setupCandidates, ['single_tall']);
    assert.equal(detected.ready, false);

    const confirmed = JSON.parse((await execFileAsync(process.execPath, [cli, 'confirm', 'mac_mini', 'single_tall', ...common])).stdout);
    assert.equal(confirmed.confirmed, true);
    assert.equal(confirmed.compatibilityMode, 'tall');
    const machine = JSON.parse(await readFile(join(stateRoot, 'machine.json'), 'utf8'));
    assert.equal(machine.hardwareProfile, 'mac_mini');
    assert.equal(machine.displayBindings.tall, 'DISPLAY-TALL-1234');
    assert.equal(machine.topologySelections['external:tall'], 'single_tall');
    const runtime = JSON.parse(await readFile(join(configRoot, 'generated', 'runtime.json'), 'utf8'));
    assert.equal(runtime.active_setup, 'single_tall');
    assert.equal(runtime.source_version, 3);

    const activated = JSON.parse((await execFileAsync(process.execPath, [cli, 'activate', ...common])).stdout);
    assert.equal(activated.activated, true);
    assert.equal(activated.compatibilityMode, 'tall');
  } finally {
    await rm(root, { recursive: true, force: true });
  }
});

test('setup CLI refuses to confirm a non-matching setup', async () => {
  const root = await mkdtemp(join(tmpdir(), 'spacewright-setup-cli-mismatch-'));
  const configRoot = join(root, 'config');
  const stateRoot = join(root, 'state');
  const snapshot = join(root, 'displays.json');
  await Promise.all([mkdir(configRoot), mkdir(stateRoot)]);
  await writeFile(join(configRoot, 'config.v3.json'), `${JSON.stringify(starterV3(), null, 2)}\n`);
  await writeFile(snapshot, JSON.stringify({ unavailable: false, displays: [{ index: 1, uuid: 'DISPLAY-WIDE-1234', frame: { w: 1920, h: 1080 }, 'is-built-in': false }] }));
  try {
    await assert.rejects(execFileAsync(process.execPath, [cli, 'confirm', 'mac_mini', 'single_tall', `--config-root=${configRoot}`, `--state-root=${stateRoot}`, `--snapshot=${snapshot}`, '--model=Macmini9,1']), (error) => {
      assert.match(error.stderr, /candidates: single_wide/);
      return true;
    });
  } finally {
    await rm(root, { recursive: true, force: true });
  }
});
