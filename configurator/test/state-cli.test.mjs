import test from 'node:test';
import assert from 'node:assert/strict';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { chmod, mkdir, mkdtemp, readFile, readdir, rm, writeFile } from 'node:fs/promises';
import { existsSync } from 'node:fs';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import { starterConfig } from '../lib/config-v2.mjs';

const execFileAsync = promisify(execFile);

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
