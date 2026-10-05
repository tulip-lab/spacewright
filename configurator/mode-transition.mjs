#!/usr/bin/env node

import { execFile, spawn } from 'node:child_process';
import { constants } from 'node:fs';
import { access, mkdir, readFile, rename, rm, stat, writeFile } from 'node:fs/promises';
import { basename, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { promisify } from 'node:util';

const VALID_MODES = new Set(['solo', 'wide', 'tall']);
const DEFAULT_TIMEOUT_MS = 120_000;
const REPLACEMENT_GRACE_MS = 4_000;
const execFileAsync = promisify(execFile);
let atomicSequence = 0;

const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

function configuredTimeoutMs() {
  const seconds = Number(process.env.SPACEWRIGHT_MODE_TIMEOUT_SECONDS || 0);
  if (!seconds) return DEFAULT_TIMEOUT_MS;
  if (!Number.isFinite(seconds) || seconds <= 0) throw new Error('SPACEWRIGHT_MODE_TIMEOUT_SECONDS must be a positive number');
  return seconds * 1000;
}

async function readJson(path, fallback = null) {
  try { return JSON.parse(await readFile(path, 'utf8')); } catch { return fallback; }
}

async function atomicWrite(path, value) {
  atomicSequence += 1;
  const temporary = `${path}.${process.pid}.${Date.now()}.${atomicSequence}.tmp`;
  await writeFile(temporary, `${JSON.stringify(value, null, 2)}\n`, { mode: 0o600 });
  await rename(temporary, path);
}

function processIsLive(pid) {
  if (!Number.isInteger(pid) || pid <= 1) return false;
  try { process.kill(pid, 0); return true; } catch (error) { return error.code === 'EPERM'; }
}

async function processOwnerKind(pid) {
  if (!processIsLive(pid)) return false;
  try {
    const { stdout } = await execFileAsync('ps', ['-p', String(pid), '-o', 'command='], { timeout: 2_000 });
    if (stdout.includes('configurator/mode-transition.mjs')) return 'mode-transition';
    if (stdout.includes('configurator/state-cli.mjs')) return 'state-cli';
    return false;
  } catch { return false; }
}

function terminateProcessGroup(pid, signal = 'SIGTERM') {
  if (!Number.isInteger(pid) || pid <= 1) return;
  try { process.kill(-pid, signal); } catch (error) {
    if (error.code !== 'ESRCH') throw error;
  }
}

function modeCommand(mode) {
  const profile = mode === 'solo' ? 'display_apply_solo' : `display_apply_${mode}_left`;
  return `workspace_run_step "display profile" ${profile}; and work_${mode}`;
}

function publicState(owner, overrides = {}) {
  return {
    schemaVersion: 1,
    runId: owner.runId,
    mode: owner.mode,
    status: 'running',
    phase: 'Preparing workspace transition',
    step: 0,
    startedAt: owner.startedAt,
    deadlineAt: owner.deadlineAt,
    timeoutSeconds: owner.timeoutSeconds,
    ...overrides,
  };
}

async function releaseOwnedLock(lockRoot, runId) {
  const owner = await readJson(join(lockRoot, 'owner.json'));
  if (owner?.runId !== runId) return;
  const released = `${lockRoot}.released-${runId}`;
  try {
    await rename(lockRoot, released);
    await rm(released, { recursive: true, force: true });
  } catch (error) {
    if (error.code !== 'ENOENT') throw error;
  }
}

async function waitForExit(pid, timeoutMs) {
  const deadline = Date.now() + timeoutMs;
  while (processIsLive(pid) && Date.now() < deadline) await sleep(50);
  return !processIsLive(pid);
}

async function replaceExistingOwner(lockRoot, requestedMode) {
  const owner = await readJson(join(lockRoot, 'owner.json'));
  const ownerKind = owner ? await processOwnerKind(owner.pid) : false;
  if (!owner) {
    const age = Date.now() - (await stat(lockRoot)).mtimeMs;
    if (age < 30_000) return { retry: true };
    const stale = `${lockRoot}.stale-${Date.now()}-${process.pid}`;
    try { await rename(lockRoot, stale); } catch (error) { if (error.code !== 'ENOENT') throw error; }
    await rm(stale, { recursive: true, force: true });
    return { replaced: false };
  }

  if (!ownerKind) {
    if (processIsLive(owner.pid)) throw new Error(`the SpaceWright execution lock has an unrecognized live owner (pid ${owner.pid}); refusing to replace it`);
    const stale = `${lockRoot}.stale-${Date.now()}-${process.pid}`;
    try { await rename(lockRoot, stale); } catch (error) { if (error.code !== 'ENOENT') throw error; }
    await rm(stale, { recursive: true, force: true });
    return { replaced: false };
  }

  if (ownerKind !== 'mode-transition') {
    throw new Error(`another SpaceWright mutation is active (run ${owner.runId || 'unknown'}, pid ${owner.pid}); wait for it to finish or cancel it`);
  }

  if (owner.mode === requestedMode) return { duplicate: true, owner };

  terminateProcessGroup(owner.childPid);
  try { process.kill(owner.pid, 'SIGTERM'); } catch (error) { if (error.code !== 'ESRCH') throw error; }
  if (!(await waitForExit(owner.pid, REPLACEMENT_GRACE_MS))) {
    try { process.kill(owner.pid, 'SIGKILL'); } catch (error) { if (error.code !== 'ESRCH') throw error; }
    await waitForExit(owner.pid, 1_000);
  }

  const current = await readJson(join(lockRoot, 'owner.json'));
  if (current?.runId === owner.runId) {
    const stale = `${lockRoot}.replaced-${owner.runId}`;
    try { await rename(lockRoot, stale); } catch (error) { if (error.code !== 'ENOENT') throw error; }
    await rm(stale, { recursive: true, force: true });
  }
  return { replaced: true, owner };
}

async function acquireLock(lockRoot, requestedMode, owner) {
  for (let attempt = 0; attempt < 20; attempt += 1) {
    try {
      await mkdir(lockRoot, { recursive: false, mode: 0o700 });
      await atomicWrite(join(lockRoot, 'owner.json'), owner);
      return { acquired: true };
    } catch (error) {
      if (error.code !== 'EEXIST') throw error;
      const result = await replaceExistingOwner(lockRoot, requestedMode);
      if (result.duplicate) return { acquired: false, duplicate: true, owner: result.owner };
      if (result.retry) await sleep(50);
    }
  }
  throw new Error('could not acquire the workspace transition lock');
}

function attachLineParser(stream, destination, onLine) {
  let buffered = '';
  stream.setEncoding('utf8');
  stream.on('data', (chunk) => {
    destination.write(chunk);
    buffered += chunk;
    const lines = buffered.split('\n');
    buffered = lines.pop() || '';
    for (const line of lines) onLine(line);
  });
  stream.on('end', () => { if (buffered) onLine(buffered); });
}

async function resolveBanner(packageRoot) {
  if (process.env.SPACEWRIGHT_BANNER_DISABLE === '1') return null;
  const candidates = [
    join(packageRoot, 'bin', 'spacewright-banner'),
    join(packageRoot, 'helpers', 'spacewright-banner'),
  ];
  for (const candidate of candidates) {
    try { await access(candidate, constants.X_OK); return candidate; } catch {}
  }
  return null;
}

export async function runTransition({
  mode,
  packageRoot,
  stateRoot,
  timeoutMs = configuredTimeoutMs(),
  fishExecutable = process.env.SPACEWRIGHT_TRANSITION_FISH || 'fish',
  command = modeCommand(mode),
  bannerExecutable,
} = {}) {
  if (!VALID_MODES.has(mode)) throw new Error(`invalid mode: ${mode}`);
  await mkdir(stateRoot, { recursive: true, mode: 0o700 });

  const transitionRoot = join(stateRoot, 'mode-transition');
  const lockRoot = join(stateRoot, 'execution.lock');
  const stateFile = join(transitionRoot, 'status.json');
  const cancelFile = join(transitionRoot, 'cancel');
  await mkdir(transitionRoot, { recursive: true, mode: 0o700 });
  await rm(cancelFile, { force: true });

  const now = Date.now();
  const runId = `${now}-${process.pid}-${Math.random().toString(16).slice(2, 10)}`;
  const owner = {
    runId,
    mode,
    pid: process.pid,
    childPid: null,
    startedAt: new Date(now).toISOString(),
    deadlineAt: new Date(now + timeoutMs).toISOString(),
    timeoutSeconds: Math.ceil(timeoutMs / 1000),
    controller: 'mode-transition',
  };
  const lock = await acquireLock(lockRoot, mode, owner);
  if (lock.duplicate) {
    process.stderr.write(`[INFO] SpaceWright ${mode} transition is already running; duplicate request ignored\n`);
    return { status: 'duplicate', runId: lock.owner.runId, mode };
  }

  let state = publicState(owner);
  await atomicWrite(stateFile, state);

  let banner = null;
  const resolvedBanner = bannerExecutable === undefined ? await resolveBanner(packageRoot) : bannerExecutable;
  if (resolvedBanner) {
    banner = spawn(resolvedBanner, [stateFile, cancelFile, runId], { stdio: 'ignore' });
    banner.on('error', () => {});
  }

  let child = null;
  let requestedReason = null;
  let step = 0;
  let stateWrites = Promise.resolve();
  const updateState = async (overrides) => {
    stateWrites = stateWrites.then(async () => {
      state = { ...state, ...overrides };
      await atomicWrite(stateFile, state);
    });
    await stateWrites;
  };
  const requestStop = (reason) => {
    if (requestedReason) return;
    requestedReason = reason;
    if (child?.pid) {
      terminateProcessGroup(child.pid);
      const childPid = child.pid;
      const escalation = setTimeout(() => terminateProcessGroup(childPid, 'SIGKILL'), 2_000);
      escalation.unref();
    }
  };
  const onTerm = () => requestStop('replaced');
  const onInterrupt = () => requestStop('cancelled');
  process.once('SIGTERM', onTerm);
  process.once('SIGINT', onInterrupt);

  const cancelPoll = setInterval(async () => {
    try {
      const requestedRunId = (await readFile(cancelFile, 'utf8')).trim();
      if (requestedRunId === runId) requestStop('cancelled');
    } catch {}
  }, 150);
  const timeout = setTimeout(() => requestStop('timed_out'), timeoutMs);

  try {
    child = spawn(fishExecutable, ['-lc', command], {
      detached: true,
      env: { ...process.env, SPACEWRIGHT_TRANSITION_RUN_ID: runId },
      stdio: ['ignore', 'pipe', 'pipe'],
    });
    const childResult = new Promise((resolve) => {
      child.once('error', (error) => resolve({ error }));
      child.once('exit', (code, signal) => resolve({ code, signal }));
    });
    owner.childPid = child.pid;
    await atomicWrite(join(lockRoot, 'owner.json'), owner);

    if (requestedReason) terminateProcessGroup(child.pid);

    const inspectLine = (line) => {
      const match = line.match(/^==>\s+(.+)$/);
      if (!match) return;
      step += 1;
      void updateState({ phase: match[1], step });
    };
    attachLineParser(child.stdout, process.stdout, inspectLine);
    attachLineParser(child.stderr, process.stderr, inspectLine);

    const exitCode = await childResult;
    if (exitCode.error) throw exitCode.error;
    let status = 'failed';
    let message = `Transition failed${exitCode.code === null ? ` (${exitCode.signal})` : ` with status ${exitCode.code}`}`;
    if (requestedReason === 'cancelled') { status = 'cancelled'; message = 'Transition cancelled'; }
    else if (requestedReason === 'replaced') { status = 'replaced'; message = 'A newer mode request took over'; }
    else if (requestedReason === 'timed_out') { status = 'timed_out'; message = `Stopped after ${Math.ceil(timeoutMs / 1000)} seconds`; }
    else if (exitCode.code === 0) { status = 'completed'; message = `${mode[0].toUpperCase()}${mode.slice(1)} workspace is ready`; }

    await updateState({ status, phase: message, finishedAt: new Date().toISOString() });
    return { status, runId, mode, exitCode: exitCode.code };
  } catch (error) {
    await updateState({ status: 'failed', phase: `Transition could not start: ${error.message}`, finishedAt: new Date().toISOString() });
    throw error;
  } finally {
    clearInterval(cancelPoll);
    clearTimeout(timeout);
    process.removeListener('SIGTERM', onTerm);
    process.removeListener('SIGINT', onInterrupt);
    await rm(cancelFile, { force: true });
    await releaseOwnedLock(lockRoot, runId);
  }
}

export async function cancelTransition(stateRoot) {
  const lockRoot = join(stateRoot, 'execution.lock');
  const owner = await readJson(join(lockRoot, 'owner.json'));
  if (!owner || await processOwnerKind(owner.pid) !== 'mode-transition') return { status: 'idle' };
  const transitionRoot = join(stateRoot, 'mode-transition');
  await writeFile(join(transitionRoot, 'cancel'), owner.runId, { mode: 0o600 });
  return { status: 'cancelling', runId: owner.runId, mode: owner.mode };
}

export async function transitionStatus(stateRoot) {
  const transitionRoot = join(stateRoot, 'mode-transition');
  const state = await readJson(join(transitionRoot, 'status.json'), { status: 'idle' });
  const owner = await readJson(join(stateRoot, 'execution.lock', 'owner.json'));
  return { ...state, active: Boolean(owner && await processOwnerKind(owner.pid) === 'mode-transition') };
}

async function main() {
  const [action = 'help', mode] = process.argv.slice(2);
  const option = (name, fallback) => process.argv.find((arg) => arg.startsWith(`--${name}=`))?.slice(name.length + 3) || fallback;
  const packageRoot = option('package-root', fileURLToPath(new URL('..', import.meta.url)));
  const stateRoot = option('state-root', process.env.SPACEWRIGHT_STATE_ROOT);
  if (!stateRoot) throw new Error('state root is required');

  if (action === 'run') {
    const result = await runTransition({ mode, packageRoot, stateRoot });
    if (!['completed', 'duplicate'].includes(result.status)) process.exitCode = 1;
  } else if (action === 'cancel') {
    const result = await cancelTransition(stateRoot);
    process.stdout.write(`${JSON.stringify(result)}\n`);
  } else if (action === 'status') {
    process.stdout.write(`${JSON.stringify(await transitionStatus(stateRoot), null, 2)}\n`);
  } else {
    process.stderr.write('usage: mode-transition.mjs <run MODE|cancel|status> --package-root=PATH --state-root=PATH\n');
    process.exitCode = 2;
  }
}

if (process.argv[1] && basename(process.argv[1]) === basename(fileURLToPath(import.meta.url))) {
  main().catch((error) => { process.stderr.write(`spacewright mode: ${error.message}\n`); process.exitCode = 1; });
}
