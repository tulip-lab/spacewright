#!/usr/bin/env node

import { execFile, spawn } from 'node:child_process';
import { constants } from 'node:fs';
import { access, mkdir, readFile, rename, rm, writeFile } from 'node:fs/promises';
import { basename, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { promisify } from 'node:util';
import { acquireExecution, releaseLock as sharedReleaseLock, runBounded } from './lib/execution-coordinator.mjs';
import { readTransitionHistory, writeTransitionRecord } from './lib/transition-history.mjs';
import { stableRead } from './lib/config-store.mjs';

const VALID_MODES = new Set(['solo', 'wide', 'tall']);
const DEFAULT_TIMEOUT_MS = 120_000;
const execFileAsync = promisify(execFile);
let atomicSequence = 0;


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

function modeCommand(mode) {
  const profile = mode === 'solo' ? 'display_apply_solo' : `display_apply_${mode}_left`;
  return `source "$SPACEWRIGHT_TRANSITION_PACKAGE_ROOT/conf.d/spacewright.fish"; or exit 1; workspace_run_step "display profile" ${profile}; and "$SPACEWRIGHT_TRANSITION_PACKAGE_ROOT/bin/spacewright" apply ${mode} --verified-marker --json`;
}

function workspaceCommand(workspace, mode) {
  return `source "$SPACEWRIGHT_TRANSITION_PACKAGE_ROOT/conf.d/spacewright.fish"; or exit 1; workspace_run_step "Arrange ${workspace} (${mode})" "$SPACEWRIGHT_TRANSITION_PACKAGE_ROOT/bin/spacewright" apply ${workspace} ${mode} --verified-marker --json`;
}

async function focusedSpaceLabel() {
  try {
    const { stdout } = await execFileAsync('yabai', ['-m', 'query', '--spaces', '--space'], { timeout: 2_000, maxBuffer: 200_000 });
    return String(JSON.parse(stdout).label || '');
  } catch {
    return '';
  }
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
    scope: owner.scope,
    workspace: owner.workspace,
    targetLabel: owner.targetLabel,
    hardwareLabel: owner.hardwareLabel,
    setupLabel: owner.setupLabel,
    ...overrides,
  };
}

function presentationSetupName(name = '') {
  return String(name)
    .replace(/^Single\s+/i, '')
    .replace(/\b(wide|tall|sidecar)\b/gi, (value) => value[0].toUpperCase() + value.slice(1).toLowerCase());
}

export async function resolveHardwareContext({ stateRoot, configRoot } = {}) {
  if (!stateRoot || !configRoot) return {};
  const [machine, config] = await Promise.all([
    readJson(join(stateRoot, 'machine.json'), {}),
    readJson(join(configRoot, 'config.v3.json'), {}),
  ]);
  const profileId = machine.hardwareProfile;
  const setupId = machine.activeSetup;
  const profile = config.hardwareProfiles?.[profileId];
  const setup = profile?.setups?.[setupId];
  const hardwareLabel = profile?.name || machine.detectedHardware?.productName;
  const setupLabel = presentationSetupName(setup?.name);
  return {
    ...(hardwareLabel ? { hardwareLabel } : {}),
    ...(setupLabel ? { setupLabel } : {}),
  };
}

async function releaseOwnedLock(lockRoot, runId) {
  const owner = await readJson(join(lockRoot, 'owner.json'));
  if (owner?.runId === runId && owner.pid === process.pid) await sharedReleaseLock(join(lockRoot, '..'), owner);
}
async function acquireLock(lockRoot, requestedTargetKey, owner) {
  const lease = await acquireExecution(join(lockRoot, '..'), owner, { replaceInteractive: true, inherit: false });
  if (lease.duplicate) return { duplicate: true, owner: lease.owner };
  Object.assign(owner, lease.owner);
  return { acquired: true, lease };
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
  configRoot,
  stateRoot,
  timeoutMs = configuredTimeoutMs(),
  fishExecutable = process.env.SPACEWRIGHT_TRANSITION_FISH || 'fish',
  command = modeCommand(mode),
  bannerExecutable,
  sourceSpaceLabel,
  scope = 'mode',
  workspace,
  targetKey = `mode:${mode}`,
  targetLabel,
  hardwareContext,
} = {}) {
  if (!VALID_MODES.has(mode)) throw new Error(`invalid mode: ${mode}`);
  await mkdir(stateRoot, { recursive: true, mode: 0o700 });

  const resolvedTargetLabel = targetLabel || `${mode[0].toUpperCase()}${mode.slice(1)}`;
  const resolvedHardwareContext = hardwareContext === undefined
    ? await resolveHardwareContext({ stateRoot, configRoot })
    : hardwareContext;

  const transitionRoot = join(stateRoot, 'mode-transition');
  const lockRoot = join(stateRoot, 'execution.lock');
  const stateFile = join(transitionRoot, 'status.json');
  const cancelFile = join(transitionRoot, 'cancel');
  await mkdir(transitionRoot, { recursive: true, mode: 0o700 });
  const now = Date.now();
  const runId = `${now}-${process.pid}-${Math.random().toString(16).slice(2, 10)}`;
  const owner = {
    runId,
    mode,
    scope,
    workspace,
    targetKey,
    targetLabel: resolvedTargetLabel,
    hardwareLabel: resolvedHardwareContext?.hardwareLabel,
    setupLabel: resolvedHardwareContext?.setupLabel,
    pid: process.pid,
    childPid: null,
    startedAt: new Date(now).toISOString(),
    deadlineAt: new Date(now + timeoutMs).toISOString(),
    timeoutSeconds: Math.ceil(timeoutMs / 1000),
    controller: 'mode-transition',
  };
  for(const name of (configRoot?['config.v3.json','config.v2.json']:[])) {
    try {owner.budgets=(await stableRead(join(configRoot,name),join(stateRoot,'machine.json'))).config.settings?.executionBudgets;break;}
    catch(error){if(error.code!=='ENOENT')throw error;}
  }
  const lock = await acquireLock(lockRoot, targetKey, owner);
  if (lock.duplicate) {
    process.stderr.write(`[INFO] SpaceWright ${resolvedTargetLabel} transition is already running; duplicate request ignored\n`);
    return { status: 'duplicate', runId: lock.owner.runId, mode };
  }

  let state = publicState(owner);
  const diagnostics = { warnings: [], skipped: [], errors: [], logTail: [] };
  let sourceLabel = null;
  const historyDocument = () => ({
    schemaVersion: 1,
    ...state,
    targetKey,
    sourceSpaceLabel: sourceLabel,
    durationMs: state.finishedAt ? Math.max(0, new Date(state.finishedAt).getTime() - now) : null,
    warnings: diagnostics.warnings,
    skipped: diagnostics.skipped,
    errors: diagnostics.errors,
    logTail: diagnostics.logTail,
  });

  let banner = null;
  const resolvedBanner = bannerExecutable;
  if (resolvedBanner) {
    banner = spawn(resolvedBanner, [stateFile, cancelFile, runId], { stdio: 'ignore' });
    banner.on('error', () => {});
  }

  let child = null;
  let requestedReason = null;
  const cancellation = new AbortController();
  let step = 0;
  let stateWrites = Promise.resolve();
  const updateState = async (overrides) => {
    stateWrites = stateWrites.catch(() => {}).then(async () => {
      state = { ...state, ...overrides };
      await Promise.all([atomicWrite(stateFile, state), writeTransitionRecord(stateRoot, historyDocument())]);
    });
    await stateWrites;
  };
  const rememberDiagnostic = (collection, line, limit = 30) => {
    if (!collection.includes(line)) collection.push(line);
    if (collection.length > limit) collection.splice(0, collection.length - limit);
  };
  const inspectOutput = (line, channel) => {
    const value = line.trim();
    if (!value) return;
    diagnostics.logTail.push(`${channel === 'stderr' ? 'ERR' : 'OUT'} ${value}`);
    if (diagnostics.logTail.length > 200) diagnostics.logTail.splice(0, diagnostics.logTail.length - 200);
    if (/\[WARN\]/i.test(value)) rememberDiagnostic(diagnostics.warnings, value);
    if (/skip|unavailable|no movable|not found|required (?:app|role).*unavailable/i.test(value)) rememberDiagnostic(diagnostics.skipped, value);
    if (channel === 'stderr' && /\[ERROR\]|\bfailed\b|could not|\berror:/i.test(value)) rememberDiagnostic(diagnostics.errors, value);
    const match = value.match(/^==>\s+(.+)$/);
    if (!match) return;
    step += 1;
    void updateState({ phase: match[1], step }).catch((error) => { rememberDiagnostic(diagnostics.errors, `status write failed: ${error.message}`); requestStop('failed'); });
  };
  const requestStop = (reason) => {
    if (requestedReason) return;
    requestedReason = reason;
    void lock.lease.cancel().catch(error=>process.stderr.write(`cancellation state write failed: ${error.message}\n`));
    cancellation.abort(Object.assign(new Error(reason), { code: reason === 'timed_out' ? 'SPACEWRIGHT_TIMEOUT' : 'SPACEWRIGHT_CANCELLED' }));
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
  const timeout = setTimeout(() => requestStop('timed_out'), Math.max(0, now + timeoutMs - Date.now()));

  try {
    await rm(cancelFile, { force: true });
    await updateState({});
    if (!banner && bannerExecutable === undefined) {
      const resolved = await resolveBanner(packageRoot);
      if (resolved) { banner = spawn(resolved, [stateFile, cancelFile, runId], { stdio: 'ignore' }); banner.on('error', () => {}); }
    }
    const transitionSourceLabel = sourceSpaceLabel === undefined ? await focusedSpaceLabel() : sourceSpaceLabel;
    sourceLabel = transitionSourceLabel;
    await updateState({ sourceSpaceLabel: transitionSourceLabel });
    const exitCode = await runBounded(fishExecutable, ['-lc', command], {
      graceMs:2500, deadline: now + timeoutMs, signal: cancellation.signal,
      env: { ...process.env, ...lock.lease.env, SPACEWRIGHT_CONFIG_ROOT: configRoot, SPACEWRIGHT_STATE_ROOT: stateRoot,
        SPACEWRIGHT_TRANSITION_PACKAGE_ROOT: packageRoot, SPACEWRIGHT_TRANSITION_RUN_ID: runId, SPACEWRIGHT_SOURCE_SPACE_LABEL: transitionSourceLabel },
      onChild: async (value) => { child = value; await lock.lease.trackChild(value); },
      onOutput: (channel, value) => { process[channel].write(value); for (const line of value.split('\n')) inspectOutput(line, channel); }
    });
    if (exitCode.error) throw exitCode.error;
    let status = 'failed';
    let message = `Transition failed${exitCode.code === null ? ` (${exitCode.signal})` : ` with status ${exitCode.code}`}`;
    if (exitCode.code !== 0 && diagnostics.errors.length) message = diagnostics.errors.at(-1).replace(/^\[ERROR\]\s*/, '').slice(0, 240);
    if (requestedReason === 'cancelled') { status = 'cancelled'; message = 'Transition cancelled'; }
    else if (requestedReason === 'replaced') { status = 'replaced'; message = 'A newer mode request took over'; }
    else if (requestedReason === 'timed_out') { status = 'timed_out'; message = `Stopped after ${Math.ceil(timeoutMs / 1000)} seconds`; }
    else if (exitCode.code === 0 && exitCode.stdout.split('\n').includes('SPACEWRIGHT_VERIFIED')) { status = 'completed'; message = scope === 'mode' ? `${resolvedTargetLabel} workspace is ready` : `${resolvedTargetLabel} is ready`; }

    const finishedAt = new Date().toISOString();
    await updateState({ status, phase: message, finishedAt, durationMs: Math.max(0, new Date(finishedAt).getTime() - now) });
    return { status, runId, mode, exitCode: exitCode.code };
  } catch (error) {
    rememberDiagnostic(diagnostics.errors, error.message);
    const finishedAt = new Date().toISOString();
    const status = requestedReason || (error.code === 'SPACEWRIGHT_TIMEOUT' ? 'timed_out' : error.code === 'SPACEWRIGHT_CANCELLED' ? 'cancelled' : 'failed');
    try { await updateState({ status, phase: status === 'timed_out' ? `Stopped after ${Math.ceil(timeoutMs / 1000)} seconds` : `Transition stopped: ${error.message}`, finishedAt, durationMs: Math.max(0, new Date(finishedAt).getTime() - now) }); }
    catch (writeError) { process.stderr.write(`terminal status write failed: ${writeError.message}; run=${runId} status=${status}\n`); }
    if (status !== 'failed') return { status, runId, mode, exitCode: status === 'timed_out' ? 124 : 130 };
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
  const [action = 'help', firstTarget, secondTarget] = process.argv.slice(2);
  const option = (name, fallback) => process.argv.find((arg) => arg.startsWith(`--${name}=`))?.slice(name.length + 3) || fallback;
  const packageRoot = option('package-root', fileURLToPath(new URL('..', import.meta.url)));
  const configRoot = option('config-root', process.env.SPACEWRIGHT_CONFIG_ROOT);
  const stateRoot = option('state-root', process.env.SPACEWRIGHT_STATE_ROOT);
  if (!stateRoot) throw new Error('state root is required');

  if (action === 'run') {
    const mode = firstTarget;
    const result = await runTransition({ mode, packageRoot, configRoot, stateRoot });
    if (!['completed', 'duplicate'].includes(result.status)) process.exitCode = 1;
  } else if (action === 'workspace') {
    const workspace = firstTarget;
    const mode = secondTarget;
    if (!/^[a-z][a-z0-9_]*$/.test(workspace || '')) throw new Error(`invalid workspace: ${workspace || ''}`);
    const targetLabel = option('label', `${workspace} · ${mode}`);
    const result = await runTransition({
      mode,
      packageRoot,
      configRoot,
      stateRoot,
      command: workspaceCommand(workspace, mode),
      scope: 'workspace',
      workspace,
      targetKey: `workspace:${workspace}:${mode}`,
      targetLabel,
    });
    if (!['completed', 'duplicate'].includes(result.status)) process.exitCode = 1;
  } else if (action === 'cancel') {
    const result = await cancelTransition(stateRoot);
    process.stdout.write(`${JSON.stringify(result)}\n`);
  } else if (action === 'status') {
    process.stdout.write(`${JSON.stringify(await transitionStatus(stateRoot), null, 2)}\n`);
  } else if (action === 'history') {
    process.stdout.write(`${JSON.stringify({ transitions: await readTransitionHistory(stateRoot) }, null, 2)}\n`);
  } else {
    process.stderr.write('usage: mode-transition.mjs <run MODE|workspace WORKSPACE MODE|cancel|status|history> --package-root=PATH --config-root=PATH --state-root=PATH\n');
    process.exitCode = 2;
  }
}

if (process.argv[1] && basename(process.argv[1]) === basename(fileURLToPath(import.meta.url))) {
  main().catch((error) => { process.stderr.write(`spacewright mode: ${error.message}\n`); process.exitCode = 1; });
}
