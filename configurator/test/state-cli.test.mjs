import test from 'node:test';
import assert from 'node:assert/strict';
import { execFile, spawn } from 'node:child_process';
import { promisify } from 'node:util';
import { chmod, mkdir, mkdtemp, readFile, readdir, rm, writeFile } from 'node:fs/promises';
import { existsSync } from 'node:fs';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import { starterConfig } from '../lib/config-v2.mjs';
import { starterV3 } from '../lib/config-v3.mjs';

const execFileAsync = promisify(execFile);

async function waitForPath(path, timeoutMs = 3000) {
  const deadline = Date.now() + timeoutMs;
  while (!existsSync(path) && Date.now() < deadline) await new Promise((resolve) => setTimeout(resolve, 20));
  assert.equal(existsSync(path), true, `timed out waiting for ${path}`);
}

test('apply does not reclaim a newly created lock before its owner is recorded', async () => {
  const root = await mkdtemp(join(tmpdir(), 'spacewright-lock-'));
  const stateRoot = join(root, 'state');
  await mkdir(join(stateRoot, 'execution.lock'), { recursive: true });
  try {
    await assert.rejects(execFileAsync(process.execPath, [
      new URL('../state-cli.mjs', import.meta.url).pathname,
      'apply', 'coding', 'solo',
      `--package-root=${root}`,
      `--config-root=${join(root, 'config')}`,
      `--state-root=${stateRoot}`
    ]), (error) => {
      assert.match(error.stderr, /execution lock; retry shortly/);
      return true;
    });
    assert.equal(existsSync(join(stateRoot, 'execution.lock')), true);
  } finally {
    await rm(root, { recursive: true, force: true });
  }
});

test('apply rejects a stale preflight and never invokes a mutation command', async () => {
  const root = await mkdtemp(join(tmpdir(), 'spacewright-stale-'));
  const packageRoot = join(root, 'package');
  const configRoot = join(root, 'config');
  const stateRoot = join(root, 'state');
  const fakeBin = join(root, 'fake-bin');
  const mutationMarker = join(root, 'mutation-attempted');
  const windowCounter = join(root, 'window-counter');
  await Promise.all([mkdir(join(packageRoot, 'bin'), { recursive: true }), mkdir(configRoot), mkdir(stateRoot), mkdir(fakeBin)]);
  await writeFile(join(configRoot, 'config.v2.json'), `${JSON.stringify(starterConfig(), null, 2)}\n`);
  await writeFile(join(stateRoot, 'machine.json'), `${JSON.stringify({ version: 1, displayBindings: { primary: 'DISPLAY-PRIMARY' } })}\n`);
  await writeFile(join(packageRoot, 'bin', 'spacewright'), `#!/bin/sh\ntouch "${mutationMarker}"\nexit 0\n`);
  await chmod(join(packageRoot, 'bin', 'spacewright'), 0o755);
  await writeFile(join(fakeBin, 'yabai'), `#!/bin/sh
case "$3" in
  --displays) printf '%s\n' '[{"index":1,"uuid":"DISPLAY-PRIMARY","frame":{"x":0,"y":0,"w":1200,"h":900},"is-built-in":true,"spaces":[1]}]' ;;
  --spaces) printf '%s\n' '[{"index":1,"uuid":"SPACE-CODING","display":1,"label":"coding_solo","type":"float"}]' ;;
  --windows)
    n=$(cat "${windowCounter}" 2>/dev/null || printf 0)
    n=$((n + 1))
    printf '%s\n' "$n" > "${windowCounter}"
    printf '[{"id":10,"app":"Code","display":1,"space":1,"frame":{"x":%s,"y":0,"w":600,"h":900},"can-move":true,"can-resize":true,"is-visible":true}]\n' "$n"
    ;;
esac
`);
  await chmod(join(fakeBin, 'yabai'), 0o755);

  try {
    await assert.rejects(execFileAsync(process.execPath, [
      new URL('../state-cli.mjs', import.meta.url).pathname,
      'apply', 'coding', 'solo',
      `--package-root=${packageRoot}`,
      `--config-root=${configRoot}`,
      `--state-root=${stateRoot}`
    ], { env: { ...process.env, PATH: `${fakeBin}:${process.env.PATH}` } }), (error) => {
      assert.match(error.stdout, /STALE\s+run=/);
      return true;
    });
    assert.equal(existsSync(mutationMarker), false);
    const journals = await readdir(join(stateRoot, 'runs'));
    const journal = JSON.parse(await readFile(join(stateRoot, 'runs', journals[0]), 'utf8'));
    assert.equal(journal.status, 'stale');
    assert.equal(journal.exitCode, 75);
    assert.match(journal.logs[0].line, /no mutation was attempted/);
  } finally {
    await rm(root, { recursive: true, force: true });
  }
});

test('apply cancellation during discovery never starts a mutation', async () => {
  const root = await mkdtemp(join(tmpdir(), 'spacewright-cancel-'));
  const packageRoot = join(root, 'package');
  const configRoot = join(root, 'config');
  const stateRoot = join(root, 'state');
  const fakeBin = join(root, 'fake-bin');
  const queryMarker = join(root, 'query-started');
  const mutationMarker = join(root, 'mutation-attempted');
  await Promise.all([mkdir(join(packageRoot, 'bin'), { recursive: true }), mkdir(configRoot), mkdir(stateRoot), mkdir(fakeBin)]);
  await writeFile(join(configRoot, 'config.v2.json'), `${JSON.stringify(starterConfig(), null, 2)}\n`);
  await writeFile(join(stateRoot, 'machine.json'), `${JSON.stringify({ version: 1, displayBindings: { primary: 'DISPLAY-PRIMARY' } })}\n`);
  await writeFile(join(packageRoot, 'bin', 'spacewright'), `#!/bin/sh\ntouch "${mutationMarker}"\nexit 0\n`);
  await chmod(join(packageRoot, 'bin', 'spacewright'), 0o755);
  await writeFile(join(fakeBin, 'yabai'), `#!/bin/sh
touch "${queryMarker}"
sleep 0.4
case "$3" in
  --displays) printf '%s\n' '[{"index":1,"uuid":"DISPLAY-PRIMARY","frame":{"x":0,"y":0,"w":1200,"h":900},"is-built-in":true,"spaces":[1]}]' ;;
  --spaces) printf '%s\n' '[{"index":1,"uuid":"SPACE-CODING","display":1,"label":"coding_solo","type":"float"}]' ;;
  --windows) printf '%s\n' '[{"id":10,"app":"Code","display":1,"space":1,"frame":{"x":0,"y":0,"w":600,"h":900},"can-move":true,"can-resize":true,"is-visible":true}]' ;;
esac
`);
  await chmod(join(fakeBin, 'yabai'), 0o755);

  try {
    const child = spawn(process.execPath, [
      new URL('../state-cli.mjs', import.meta.url).pathname,
      'apply', 'coding', 'solo',
      `--package-root=${packageRoot}`,
      `--config-root=${configRoot}`,
      `--state-root=${stateRoot}`
    ], { env: { ...process.env, PATH: `${fakeBin}:${process.env.PATH}` }, stdio: ['ignore', 'pipe', 'pipe'] });
    await waitForPath(queryMarker);
    child.kill('SIGTERM');
    const exitCode = await new Promise((resolve) => child.once('exit', resolve));
    assert.equal(exitCode, 130);
    assert.equal(existsSync(mutationMarker), false);
    assert.equal(existsSync(join(stateRoot, 'execution.lock')), false);
  } finally {
    await rm(root, { recursive: true, force: true });
  }
});

test('apply journals the exact incremental command and verifies convergence', async () => {
  const root = await mkdtemp(join(tmpdir(), 'spacewright-apply-'));
  const packageRoot = join(root, 'package');
  const configRoot = join(root, 'config');
  const stateRoot = join(root, 'state');
  const fakeBin = join(root, 'fake-bin');
  const mutationMarker = join(root, 'mutation-attempted');
  await Promise.all([mkdir(join(packageRoot, 'bin'), { recursive: true }), mkdir(configRoot), mkdir(stateRoot), mkdir(fakeBin)]);
  await writeFile(join(configRoot, 'config.v2.json'), `${JSON.stringify(starterConfig(), null, 2)}\n`);
  await writeFile(join(stateRoot, 'machine.json'), `${JSON.stringify({ version: 1, displayBindings: { primary: 'DISPLAY-PRIMARY' } })}\n`);
  await writeFile(join(packageRoot, 'bin', 'spacewright'), `#!/bin/sh\ntouch "${mutationMarker}"\nexit 0\n`);
  await chmod(join(packageRoot, 'bin', 'spacewright'), 0o755);
  await writeFile(join(fakeBin, 'yabai'), `#!/bin/sh
case "$3" in
  --displays) printf '%s\n' '[{"index":1,"uuid":"DISPLAY-PRIMARY","frame":{"x":0,"y":0,"w":1200,"h":900},"is-built-in":true,"spaces":[1]}]' ;;
  --spaces) printf '%s\n' '[{"index":1,"uuid":"SPACE-CODING","display":1,"label":"coding_solo","type":"float"}]' ;;
  --windows)
    if test -e "${mutationMarker}"; then width=1200; else width=600; fi
    printf '[{"id":10,"app":"Code","display":1,"space":1,"frame":{"x":0,"y":0,"w":%s,"h":900},"can-move":true,"can-resize":true,"is-visible":true}]\n' "$width"
    ;;
esac
`);
  await chmod(join(fakeBin, 'yabai'), 0o755);

  try {
    const result = await execFileAsync(process.execPath, [
      new URL('../state-cli.mjs', import.meta.url).pathname,
      'apply', 'coding', 'solo',
      `--package-root=${packageRoot}`,
      `--config-root=${configRoot}`,
      `--state-root=${stateRoot}`
    ], { env: { ...process.env, PATH: `${fakeBin}:${process.env.PATH}` } });
    assert.match(result.stdout, /OK\s+run=/);
    const journals = await readdir(join(stateRoot, 'runs'));
    const journal = JSON.parse(await readFile(join(stateRoot, 'runs', journals[0]), 'utf8'));
    assert.equal(journal.status, 'completed');
    assert.equal(journal.verification.converged, true);
    assert.equal(journal.steps.length, 1);
    assert.equal(journal.steps[0].action, 'workspace');
    assert.deepEqual(journal.steps[0].command, ['spacewright', 'run', 'coding', 'solo']);
    assert.equal(journal.steps[0].status, 'completed');

  } finally {
    await rm(root, { recursive: true, force: true });
  }
});

test('recovery writes an independent step journal before restoring windows', async () => {
  const root = await mkdtemp(join(tmpdir(), 'spacewright-recover-'));
  const stateRoot = join(root, 'state');
  const fakeBin = join(root, 'fake-bin');
  const mutationLog = join(root, 'mutations.log');
  const sourceRunId = '1700000000000-abcdef12';
  await Promise.all([mkdir(join(stateRoot, 'runs'), { recursive: true }), mkdir(fakeBin)]);
  await writeFile(join(stateRoot, 'runs', `${sourceRunId}.json`), `${JSON.stringify({
    formatVersion: 2,
    runId: sourceRunId,
    before: {
      displays: [{ index: 1, uuid: 'DISPLAY-PRIMARY', frame: { x: 0, y: 0, w: 1200, h: 900 } }],
      spaces: [{ index: 1, uuid: 'SPACE-ORIGINAL', display: 1, label: 'coding_solo' }],
      windows: [{ id: 10, pid: 100, bundleId: '', app: 'Code', space: 1, display: 1, frame: { x: 10, y: 20, w: 800, h: 700 }, movable: true, resizable: true }]
    },
    effects: [{ type: 'move_window', windowId: 10 }],
    plan: { recovery: { windowIds: [10] } }
  }, null, 2)}\n`);
  await writeFile(join(fakeBin, 'yabai'), `#!/bin/sh
if test "$2" = window; then printf '%s\n' "$*" >> "${mutationLog}"; touch "${mutationLog}.done"; exit 0; fi
case "$3" in
  --displays) printf '%s\n' '[{"index":1,"uuid":"DISPLAY-PRIMARY","frame":{"x":0,"y":0,"w":1200,"h":900},"is-built-in":true,"spaces":[1]}]' ;;
  --spaces) printf '%s\n' '[{"index":1,"uuid":"SPACE-ORIGINAL","display":1,"label":"coding_solo","type":"float"}]' ;;
  --windows) printf '%s\n' '[{"id":10,"pid":100,"app":"Code","display":1,"space":1,"frame":{"x":10,"y":20,"w":800,"h":700},"can-move":true,"can-resize":true,"is-visible":true}]' ;;
esac
`);
  await chmod(join(fakeBin, 'yabai'), 0o755);

  try {
    const { stdout } = await execFileAsync(process.execPath, [
      new URL('../state-cli.mjs', import.meta.url).pathname,
      'recover', sourceRunId,
      `--state-root=${stateRoot}`
    ], { env: { ...process.env, PATH: `${fakeBin}:${process.env.PATH}` } });
    assert.match(stdout, /OK\s+restored=1/);
    const journals = (await readdir(join(stateRoot, 'runs'))).filter((name) => name !== `${sourceRunId}.json`);
    assert.equal(journals.length, 1);
    const recovery = JSON.parse(await readFile(join(stateRoot, 'runs', journals[0]), 'utf8'));
    assert.equal(recovery.kind, 'recovery');
    assert.equal(recovery.sourceRunId, sourceRunId);
    assert.equal(recovery.status, 'completed');
    assert.deepEqual(recovery.steps.map((step) => [step.windowId, step.status]), [[10, 'completed']]);
    assert.match(await readFile(mutationLog, 'utf8'), /window 10 --space 1[\s\S]*window 10 --move abs:10:20[\s\S]*window 10 --resize abs:800:700/);
  } finally {
    await rm(root, { recursive: true, force: true });
  }
});

test('v3 plan resolves the confirmed hardware setup without a mode argument', async () => {
  const root = await mkdtemp(join(tmpdir(), 'spacewright-v3-plan-'));
  const configRoot = join(root, 'config');
  const stateRoot = join(root, 'state');
  const fakeBin = join(root, 'fake-bin');
  await Promise.all([mkdir(configRoot), mkdir(stateRoot), mkdir(fakeBin)]);
  const config = starterV3();
  await writeFile(join(configRoot, 'config.v3.json'), `${JSON.stringify(config, null, 2)}\n`);
  await writeFile(join(stateRoot, 'machine.json'), `${JSON.stringify({
    version: 2,
    hardwareProfile: 'mac_mini',
    hardwareProfileConfirmed: true,
    displayBindings: { tall: 'DISPLAY-TALL' },
    displayKinds: {},
    topologySelections: { 'external:tall': 'single_tall' },
    activeSetup: 'single_tall'
  }, null, 2)}\n`);
  await writeFile(join(fakeBin, 'sysctl'), '#!/bin/sh\nprintf "%s\\n" "Macmini9,1"\n');
  await writeFile(join(fakeBin, 'yabai'), `#!/bin/sh
case "$3" in
  --displays) printf '%s\n' '[{"index":1,"uuid":"DISPLAY-TALL","frame":{"x":0,"y":0,"w":1200,"h":1920},"is-built-in":false,"spaces":[1]}]' ;;
  --spaces) printf '%s\n' '[{"index":1,"uuid":"SPACE-CODING","display":1,"label":"coding_tall","type":"float"}]' ;;
  --windows) printf '%s\n' '[{"id":10,"app":"Code","display":1,"space":1,"frame":{"x":0,"y":0,"w":1200,"h":1920},"can-move":true,"can-resize":true,"is-visible":true}]' ;;
esac
`);
  await Promise.all([chmod(join(fakeBin, 'sysctl'), 0o755), chmod(join(fakeBin, 'yabai'), 0o755)]);
  try {
    const { stdout } = await execFileAsync(process.execPath, [
      new URL('../state-cli.mjs', import.meta.url).pathname,
      'plan', 'coding', '--json',
      `--package-root=${new URL('../..', import.meta.url).pathname}`,
      `--config-root=${configRoot}`,
      `--state-root=${stateRoot}`
    ], { env: { ...process.env, PATH: `${fakeBin}:${process.env.PATH}` } });
    const plan = JSON.parse(stdout);
    assert.equal(plan.plan.target.kind, 'workspace');
    assert.equal(plan.plan.target.id, 'coding');
    assert.equal(plan.plan.target.mode, 'tall');
    assert.equal(plan.desired.workspaces[0].label, 'coding_tall');
    assert.equal(plan.plan.executable, true);
  } finally {
    await rm(root, { recursive: true, force: true });
  }
});
