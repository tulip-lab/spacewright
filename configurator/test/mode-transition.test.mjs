import test from 'node:test';
import assert from 'node:assert/strict';
import { execFile, spawn } from 'node:child_process';
import { promisify } from 'node:util';
import { chmod, mkdir, mkdtemp, readFile, rm, writeFile } from 'node:fs/promises';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import { runTransition } from '../mode-transition.mjs';

const execFileAsync = promisify(execFile);
const script = new URL('../mode-transition.mjs', import.meta.url).pathname;
const stateCli = new URL('../state-cli.mjs', import.meta.url).pathname;

async function waitFor(predicate, timeoutMs = 5_000) {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    if (await predicate()) return;
    await new Promise((resolve) => setTimeout(resolve, 25));
  }
  throw new Error('timed out waiting for transition state');
}

async function waitForChild(child) {
  if (child.exitCode !== null || child.signalCode !== null) return;
  await new Promise((resolve) => child.once('exit', resolve));
}

async function fixture() {
  const root = await mkdtemp(join(tmpdir(), 'spacewright-mode-'));
  const stateRoot = join(root, 'state');
  const fakeFish = join(root, 'fake-fish');
  const log = join(root, 'runs.log');
  await writeFile(fakeFish, `#!/bin/sh
trap 'printf "stopped %s\\n" "$2" >> "$FAKE_LOG"; exit 143' TERM INT
printf 'started %s\\n' "$2" >> "$FAKE_LOG"
printf '==> fake workspace step\\n'
sleep "$FAKE_DURATION" &
wait $!
printf 'completed %s\\n' "$2" >> "$FAKE_LOG"
`);
  await chmod(fakeFish, 0o755);
  return { root, stateRoot, fakeFish, log };
}

function args(stateRoot, mode) {
  return [script, 'run', mode, `--package-root=${process.cwd()}`, `--state-root=${stateRoot}`];
}

test('a repeated request for the same mode is coalesced', async () => {
  const { root, stateRoot, fakeFish, log } = await fixture();
  const env = { ...process.env, SPACEWRIGHT_BANNER_DISABLE: '1', SPACEWRIGHT_TRANSITION_FISH: fakeFish, FAKE_LOG: log, FAKE_DURATION: '2' };
  const first = spawn(process.execPath, args(stateRoot, 'wide'), { env, stdio: ['ignore', 'pipe', 'pipe'] });
  try {
    await waitFor(async () => (await readFile(log, 'utf8').catch(() => '')).includes('started'));
    const duplicate = await execFileAsync(process.execPath, args(stateRoot, 'wide'), { env });
    assert.match(duplicate.stderr, /duplicate request ignored/);
    assert.equal((await readFile(log, 'utf8')).match(/started/g)?.length, 1);
  } finally {
    first.kill('SIGTERM');
    await waitForChild(first);
    await rm(root, { recursive: true, force: true });
  }
});

test('an immediately completed child cannot outrun exit observation', async () => {
  const root = await mkdtemp(join(tmpdir(), 'spacewright-mode-fast-'));
  const stateRoot = join(root, 'state');
  const env = { ...process.env, SPACEWRIGHT_BANNER_DISABLE: '1', SPACEWRIGHT_TRANSITION_FISH: '/usr/bin/true' };
  try {
    await execFileAsync(process.execPath, args(stateRoot, 'wide'), { env, timeout: 2_000 });
    const status = JSON.parse(await readFile(join(stateRoot, 'mode-transition', 'status.json'), 'utf8'));
    assert.equal(status.status, 'completed');
  } finally {
    await rm(root, { recursive: true, force: true });
  }
});

test('the pre-transition workspace label is passed to the Fish run', async () => {
  const root = await mkdtemp(join(tmpdir(), 'spacewright-mode-source-'));
  const stateRoot = join(root, 'state');
  const fakeFish = join(root, 'fake-fish');
  const log = join(root, 'source.log');
  await writeFile(fakeFish, `#!/bin/sh\nprintf '%s\\n' "$SPACEWRIGHT_SOURCE_SPACE_LABEL" > ${JSON.stringify(log)}\n`);
  await chmod(fakeFish, 0o755);
  try {
    await runTransition({ mode: 'solo', packageRoot: process.cwd(), stateRoot, fishExecutable: fakeFish, bannerExecutable: null, sourceSpaceLabel: 'research_wide' });
    assert.equal((await readFile(log, 'utf8')).trim(), 'research_wide');
  } finally {
    await rm(root, { recursive: true, force: true });
  }
});

test('state reconciliation cannot overlap an active mode transition', async () => {
  const { root, stateRoot, fakeFish, log } = await fixture();
  const env = { ...process.env, SPACEWRIGHT_BANNER_DISABLE: '1', SPACEWRIGHT_TRANSITION_FISH: fakeFish, FAKE_LOG: log, FAKE_DURATION: '2' };
  const transition = spawn(process.execPath, args(stateRoot, 'wide'), { env, stdio: ['ignore', 'pipe', 'pipe'] });
  try {
    await waitFor(async () => (await readFile(log, 'utf8').catch(() => '')).includes('started'));
    await assert.rejects(execFileAsync(process.execPath, [
      stateCli, 'apply', 'wide',
      `--package-root=${root}`,
      `--config-root=${join(root, 'config')}`,
      `--state-root=${stateRoot}`,
    ], { env }), (error) => {
      assert.match(error.stderr, /another SpaceWright mutation is active/);
      return true;
    });
  } finally {
    transition.kill('SIGTERM');
    await waitForChild(transition);
    await rm(root, { recursive: true, force: true });
  }
});

test('a mode transition does not replace an active state reconciliation run', async () => {
  const { root, stateRoot, fakeFish, log } = await fixture();
  const fakeConfigurator = join(root, 'configurator');
  const ownerScript = join(fakeConfigurator, 'state-cli.mjs');
  await mkdir(fakeConfigurator, { recursive: true });
  await writeFile(ownerScript, `
    import { mkdir, writeFile } from 'node:fs/promises';
    const lock = ${JSON.stringify(join(stateRoot, 'execution.lock'))};
    await mkdir(lock, { recursive: true });
    await writeFile(lock + '/owner.json', JSON.stringify({ runId: 'state-run', pid: process.pid, controller: 'state-cli' }));
    setTimeout(() => process.exit(0), 5000);
  `);
  const owner = spawn(process.execPath, [ownerScript], { stdio: 'ignore' });
  const env = { ...process.env, SPACEWRIGHT_BANNER_DISABLE: '1', SPACEWRIGHT_TRANSITION_FISH: fakeFish, FAKE_LOG: log, FAKE_DURATION: '0.1' };
  try {
    await waitFor(async () => (await readFile(join(stateRoot, 'execution.lock', 'owner.json'), 'utf8').catch(() => '')).includes('state-run'));
    await assert.rejects(execFileAsync(process.execPath, args(stateRoot, 'solo'), { env }), (error) => {
      assert.match(error.stderr, /another SpaceWright mutation is active/);
      return true;
    });
    assert.equal(await readFile(log, 'utf8').catch(() => ''), '');
  } finally {
    owner.kill('SIGTERM');
    await waitForChild(owner);
    await rm(root, { recursive: true, force: true });
  }
});

test('a newer different mode replaces the active transition', async () => {
  const { root, stateRoot, fakeFish, log } = await fixture();
  const common = { ...process.env, SPACEWRIGHT_BANNER_DISABLE: '1', SPACEWRIGHT_TRANSITION_FISH: fakeFish, FAKE_LOG: log };
  const first = spawn(process.execPath, args(stateRoot, 'wide'), { env: { ...common, FAKE_DURATION: '10' }, stdio: ['ignore', 'pipe', 'pipe'] });
  try {
    await waitFor(async () => (await readFile(log, 'utf8').catch(() => '')).includes('work_wide'));
    await execFileAsync(process.execPath, args(stateRoot, 'solo'), { env: { ...common, FAKE_DURATION: '0.1' } });
    await waitForChild(first);
    const lines = await readFile(log, 'utf8');
    assert.match(lines, /started .*work_wide/);
    assert.match(lines, /started .*work_solo/);
    assert.doesNotMatch(lines, /completed .*work_wide/);
    assert.match(lines, /completed .*work_solo/);
    const status = JSON.parse(await readFile(join(stateRoot, 'mode-transition', 'status.json'), 'utf8'));
    assert.equal(status.mode, 'solo');
    assert.equal(status.status, 'completed');
  } finally {
    if (first.exitCode === null) first.kill('SIGKILL');
    await rm(root, { recursive: true, force: true });
  }
});

test('the cancellation command records cancellation and stops the child group', async () => {
  const { root, stateRoot, fakeFish, log } = await fixture();
  const env = { ...process.env, SPACEWRIGHT_BANNER_DISABLE: '1', SPACEWRIGHT_TRANSITION_FISH: fakeFish, FAKE_LOG: log, FAKE_DURATION: '10' };
  const transition = spawn(process.execPath, args(stateRoot, 'wide'), { env, stdio: ['ignore', 'pipe', 'pipe'] });
  try {
    await waitFor(async () => (await readFile(log, 'utf8').catch(() => '')).includes('started'));
    const result = await execFileAsync(process.execPath, [script, 'cancel', `--package-root=${process.cwd()}`, `--state-root=${stateRoot}`], { env });
    assert.equal(JSON.parse(result.stdout).status, 'cancelling');
    await waitForChild(transition);
    const status = JSON.parse(await readFile(join(stateRoot, 'mode-transition', 'status.json'), 'utf8'));
    assert.equal(status.status, 'cancelled');
    assert.doesNotMatch(await readFile(log, 'utf8'), /completed/);
  } finally {
    if (transition.exitCode === null) transition.kill('SIGKILL');
    await rm(root, { recursive: true, force: true });
  }
});

test('a transition is stopped at its safety deadline', async () => {
  const { root, stateRoot, fakeFish, log } = await fixture();
  const env = {
    ...process.env,
    SPACEWRIGHT_BANNER_DISABLE: '1',
    SPACEWRIGHT_TRANSITION_FISH: fakeFish,
    SPACEWRIGHT_MODE_TIMEOUT_SECONDS: '0.2',
    FAKE_LOG: log,
    FAKE_DURATION: '10',
  };
  try {
    await assert.rejects(execFileAsync(process.execPath, args(stateRoot, 'tall'), { env }));
    const status = JSON.parse(await readFile(join(stateRoot, 'mode-transition', 'status.json'), 'utf8'));
    assert.equal(status.status, 'timed_out');
    assert.match(status.phase, /Stopped after 1 seconds/);
  } finally {
    await rm(root, { recursive: true, force: true });
  }
});
