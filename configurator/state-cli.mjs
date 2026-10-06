#!/usr/bin/env node

import { execFile, spawn } from 'node:child_process';
import { promisify } from 'node:util';
import { existsSync } from 'node:fs';
import { mkdir, readFile, rename, rm, stat, writeFile } from 'node:fs/promises';
import { dirname, join, resolve } from 'node:path';
import { randomBytes } from 'node:crypto';
import { buildDesiredState, buildExecutionPlan, captureWorkspace, compareState, normalizeSnapshot, summarizeComparison } from './lib/state-engine.mjs';
import { compileV2, validateV2 } from './lib/config-v2.mjs';

const execFileAsync = promisify(execFile);
const command = process.argv[2] || 'help';
const positional = process.argv.slice(3).filter((value) => !value.startsWith('--'));
const flags = Object.fromEntries(process.argv.slice(3).filter((value) => value.startsWith('--')).map((value) => {
  const [key, ...rest] = value.slice(2).split('=');
  return [key, rest.length ? rest.join('=') : true];
}));
const packageRoot = resolve(flags['package-root'] || join(import.meta.dirname, '..'));
const configRoot = resolve(flags['config-root'] || process.env.SPACEWRIGHT_CONFIG_ROOT || join(process.env.HOME, '.config', 'spacewright'));
const stateRoot = resolve(flags['state-root'] || process.env.SPACEWRIGHT_STATE_ROOT || join(process.env.HOME, '.local', 'state', 'spacewright'));
const configFile = join(configRoot, 'config.v2.json');
const machineFile = join(stateRoot, 'machine.json');
const executable = join(packageRoot, 'bin', 'spacewright');

async function readJson(path, fallback) {
  if (!existsSync(path)) return structuredClone(fallback);
  return JSON.parse(await readFile(path, 'utf8'));
}

async function atomicWrite(path, value) {
  await mkdir(dirname(path), { recursive: true, mode: 0o700 });
  const temporary = `${path}.tmp-${process.pid}`;
  await writeFile(temporary, `${JSON.stringify(value, null, 2)}\n`, { mode: 0o600 });
  await rename(temporary, path);
}

async function query(kind, maxBuffer = 4_000_000) {
  const { stdout } = await execFileAsync('yabai', ['-m', 'query', `--${kind}`], { timeout: 5000, maxBuffer });
  return JSON.parse(stdout);
}

export async function discover(machineOverride = null) {
  const capturedAt = new Date().toISOString();
  const machine = machineOverride || await readJson(machineFile, { version: 1, displayBindings: {} });
  try {
    const [displays, spaces, windows] = await Promise.all([
      query('displays', 1_000_000), query('spaces', 2_000_000), query('windows')
    ]);
    return normalizeSnapshot({ capturedAt, displays, spaces, windows }, machine);
  } catch (error) {
    return normalizeSnapshot({ capturedAt, unavailable: true, message: `live yabai discovery failed: ${error.message}`, displays: [], spaces: [], windows: [] }, machine);
  }
}

async function context() {
  if (!existsSync(configFile)) throw new Error(`v2 configuration not found at ${configFile}; run “spacewright configure” first`);
  const [config, machine] = await Promise.all([readJson(configFile, null), readJson(machineFile, { version: 1, displayBindings: {} })]);
  const snapshot = await discover(machine);
  const validation = validateV2(config);
  if (!validation.valid) throw new Error(`configuration is invalid:\n${validation.errors.join('\n')}`);
  return { config, machine, snapshot, runtime: compileV2(config) };
}

function parseTarget(values = positional) {
  if (flags.profile) return { kind: 'profile', id: String(flags.profile) };
  const id = values[0];
  const mode = values[1];
  if (!id) throw new Error('target is required; use a workspace id plus mode, a mode name, or --profile=<id>');
  if (['solo', 'wide', 'tall'].includes(id) && !mode) return { kind: 'mode', id, mode: id };
  return { kind: 'workspace', id, mode };
}

async function livePlan(target = parseTarget()) {
  const value = await context();
  const desired = buildDesiredState(value.config, value.runtime, target, value.snapshot);
  const comparison = compareState(value.snapshot, desired, value.machine);
  const plan = buildExecutionPlan(value.snapshot, desired, comparison);
  return { ...value, desired, comparison, plan };
}

function print(value) {
  process.stdout.write(`${JSON.stringify(value, null, 2)}\n`);
}

function printInspect(snapshot) {
  if (snapshot.unavailable) {
    console.error(`UNAVAILABLE  ${snapshot.message}`);
    return;
  }
  console.log(`snapshot=${snapshot.snapshotId}`);
  console.log(`displays=${snapshot.displays.length} spaces=${snapshot.spaces.length} windows=${snapshot.windows.length}`);
  for (const display of snapshot.displays) {
    console.log(`\nDISPLAY ${display.index} ${display.role || 'unbound'} ${display.uuid} ${display.frame.w}x${display.frame.h}`);
    for (const space of snapshot.spaces.filter((item) => item.display === display.index)) {
      const apps = snapshot.windows.filter((window) => window.space === space.index).map((window) => window.app);
      console.log(`  SPACE ${space.index} ${space.label || '(unlabeled)'} windows=${apps.length}${space.focused ? ' focused' : ''}`);
      for (const app of apps) console.log(`    ${app}`);
    }
  }
}

function printPlan(plan, comparison) {
  console.log(`plan=${plan.planId}`);
  console.log(`target=${plan.target.kind}:${plan.target.id}:${plan.target.mode}`);
  console.log(`snapshot=${plan.snapshotId}`);
  console.log(`status=${plan.executable ? 'executable' : 'blocked'} ${summarizeComparison(comparison)}`);
  for (const blocker of plan.blockers) console.log(`BLOCK   ${blocker.code} ${blocker.workspaceId || ''} ${blocker.role || ''}`.trimEnd());
  for (const warning of plan.warnings) console.log(`WARN    ${warning.code} ${warning.workspaceId || ''} ${warning.role || ''}`.trimEnd());
  if (!plan.actions.length) console.log('OK      no changes required');
  for (const [index, action] of plan.actions.entries()) {
    const subject = action.workspaceId
      || action.mode
      || action.profile
      || (action.spaceIndex ? `space=${action.spaceIndex} display=${action.display}${action.label ? ` label=${action.label}` : ''}` : '');
    console.log(`${String(index + 1).padStart(2, '0')}      ${action.type} ${subject} ${action.role || ''}`.trimEnd());
  }
  for (const step of plan.executionSteps || []) console.log(`RUN     spacewright ${step.command.join(' ')}`);
}

async function acquireLock(runId) {
  const lockRoot = join(stateRoot, 'execution.lock');
  try {
    await mkdir(lockRoot, { recursive: false, mode: 0o700 });
  } catch (error) {
    if (error.code !== 'EEXIST') throw error;
    const owner = await readJson(join(lockRoot, 'owner.json'), {});
    let live = false;
    if (Number.isInteger(owner.pid)) {
      try {
        process.kill(owner.pid, 0);
        const { stdout } = await execFileAsync('ps', ['-p', String(owner.pid), '-o', 'command='], { timeout: 2000 });
        live = stdout.includes('configurator/state-cli.mjs') || stdout.includes('configurator/mode-transition.mjs');
      } catch {}
    } else {
      const age = Date.now() - (await stat(lockRoot)).mtimeMs;
      if (age < 30_000) throw new Error('another SpaceWright mutation is acquiring the execution lock; retry shortly');
    }
    if (live) throw new Error(`another SpaceWright mutation is active (run ${owner.runId || 'unknown'}, pid ${owner.pid}); wait for it to finish or cancel it`);
    const staleRoot = `${lockRoot}.stale-${runId}`;
    try { await rename(lockRoot, staleRoot); }
    catch (renameError) {
      if (renameError.code === 'ENOENT') return acquireLock(runId);
      throw renameError;
    }
    await rm(staleRoot, { recursive: true, force: true });
    try { await mkdir(lockRoot, { recursive: false, mode: 0o700 }); }
    catch (mkdirError) {
      if (mkdirError.code === 'EEXIST') throw new Error('another SpaceWright mutation acquired the execution lock; retry shortly');
      throw mkdirError;
    }
  }
  await atomicWrite(join(lockRoot, 'owner.json'), { runId, pid: process.pid, controller: 'state-cli', acquiredAt: new Date().toISOString() });
  return async () => {
    const owner = await readJson(join(lockRoot, 'owner.json'), {});
    if (owner.runId !== runId || owner.pid !== process.pid) return;
    const releasedRoot = `${lockRoot}.released-${runId}`;
    try { await rename(lockRoot, releasedRoot); }
    catch (error) {
      if (error.code === 'ENOENT') return;
      throw error;
    }
    await rm(releasedRoot, { recursive: true, force: true });
  };
}

async function runCommand(args, journal, journalFile, plannedStep, attempt = 0) {
  const step = { ...plannedStep, attempt, status: 'running', command: ['spacewright', ...args], startedAt: new Date().toISOString() };
  journal.steps.push(step);
  await atomicWrite(journalFile, journal);
  const child = spawn(executable, args, { env: { ...process.env, SPACEWRIGHT_CONFIG_ROOT: configRoot, SPACEWRIGHT_STATE_ROOT: stateRoot }, detached: true, stdio: ['ignore', 'pipe', 'pipe'] });
  activeChild = child;
  journal.childPid = child.pid;
  const completion = new Promise((resolveRun) => {
    let settled = false;
    const finish = (exitCode) => {
      if (settled) return;
      settled = true; activeChild = null; delete journal.childPid;
      step.status = exitCode === 0 ? 'completed' : 'failed'; step.exitCode = exitCode; step.finishedAt = new Date().toISOString();
      resolveRun(exitCode);
    };
    const append = (stream) => (chunk) => {
      for (const line of String(chunk).split('\n').filter(Boolean)) journal.logs.push({ timestamp: new Date().toISOString(), stream, line });
    };
    child.stdout.on('data', append('stdout'));
    child.stderr.on('data', append('stderr'));
    child.once('error', (error) => {
      journal.logs.push({ timestamp: new Date().toISOString(), stream: 'system', line: error.message });
      finish(1);
    });
    child.once('exit', (code, signal) => {
      finish(code ?? (signal ? 130 : 1));
    });
  });
  await atomicWrite(journalFile, journal);
  return await completion;
}

let activeChild = null;
for (const signal of ['SIGINT', 'SIGTERM']) process.on(signal, () => {
  if (activeChild?.pid) try { process.kill(-activeChild.pid, 'SIGTERM'); } catch {}
  process.exitCode = 130;
});

async function applyPlan(target) {
  const runId = `${Date.now()}-${randomBytes(4).toString('hex')}`;
  const releaseLock = await acquireLock(runId);
  try {
    const initial = await livePlan(target);
    if (initial.snapshot.unavailable) throw new Error(initial.snapshot.message);
    const expected = {
      planId: flags['expected-plan-id'],
      configDigest: flags['expected-config-digest'],
      snapshotId: flags['expected-snapshot-id']
    };
    if ((expected.planId && expected.planId !== initial.plan.planId)
      || (expected.configDigest && expected.configDigest !== initial.plan.configDigest)
      || (expected.snapshotId && expected.snapshotId !== initial.snapshot.snapshotId)) {
      return { stale: true, status: 'stale', exitCode: 75, expected, actual: { planId: initial.plan.planId, configDigest: initial.plan.configDigest, snapshotId: initial.snapshot.snapshotId }, plan: initial.plan, comparison: initial.comparison };
    }
    if (!initial.plan.executable) throw new Error(`plan ${initial.plan.planId} is blocked: ${initial.plan.blockers.map((item) => item.code).join(', ')}`);
    if (!initial.plan.actions.length) return { noop: true, plan: initial.plan, comparison: initial.comparison };
    const journalFile = join(stateRoot, 'runs', `${runId}.json`);
    const journal = {
      formatVersion: 2,
      runId,
      status: 'preflight',
      createdAt: new Date().toISOString(),
      target: initial.plan.target,
      plan: initial.plan,
      before: initial.snapshot,
      steps: [],
      logs: [],
      exitCode: 0
    };
    await atomicWrite(journalFile, journal);
    const preflight = await livePlan(target);
    if (preflight.plan.configDigest !== initial.plan.configDigest || preflight.snapshot.snapshotId !== initial.snapshot.snapshotId || preflight.plan.planId !== initial.plan.planId) {
      journal.status = 'stale'; journal.exitCode = 75; journal.finishedAt = new Date().toISOString();
      journal.preflight = { snapshotId: preflight.snapshot.snapshotId, planId: preflight.plan.planId, configDigest: preflight.plan.configDigest };
      journal.logs.push({ timestamp: journal.finishedAt, stream: 'system', line: 'preflight state changed after planning; no mutation was attempted' });
      await atomicWrite(journalFile, journal);
      return { runId, status: journal.status, exitCode: journal.exitCode, plan: initial.plan, journal: journalFile, stale: journal.preflight };
    }
    journal.status = 'running';
    await atomicWrite(journalFile, journal);
    for (const step of initial.plan.executionSteps) {
      journal.exitCode = await runCommand(step.command, journal, journalFile, step, 0);
      await atomicWrite(journalFile, journal);
      if (journal.exitCode !== 0) break;
    }
    let verification = await livePlan(target);
    journal.after = verification.snapshot;
    journal.verification = verification.comparison;
    if (journal.exitCode === 0 && !verification.comparison.converged && verification.plan.executable && verification.plan.actions.length && initial.plan.recovery.automaticAttempts > 0 && !flags['no-reconcile']) {
      journal.steps.push({ type: 'reconciliation', status: 'started', startedAt: new Date().toISOString(), remaining: verification.comparison.counts, planId: verification.plan.planId });
      await atomicWrite(journalFile, journal);
      for (const step of verification.plan.executionSteps) {
        journal.exitCode = await runCommand(step.command, journal, journalFile, step, 1);
        await atomicWrite(journalFile, journal);
        if (journal.exitCode !== 0) break;
      }
      verification = await livePlan(target);
      journal.after = verification.snapshot;
      journal.verification = verification.comparison;
    }
    journal.status = journal.exitCode === 0 && journal.verification.converged ? 'completed' : 'failed';
    journal.finishedAt = new Date().toISOString();
    await atomicWrite(journalFile, journal);
    return { runId, status: journal.status, exitCode: journal.exitCode, plan: initial.plan, verification: journal.verification, journal: journalFile };
  } finally {
    await releaseLock();
  }
}

async function restoreRun(runId) {
  if (!/^[0-9]+-[a-f0-9]{8}$/.test(runId)) throw new Error('invalid run id; expected the id printed by “spacewright apply”');
  const journalFile = join(stateRoot, 'runs', `${runId}.json`);
  const journal = await readJson(journalFile, null);
  if (!journal?.before) throw new Error(`run ${runId} has no recovery snapshot`);
  const recoverableWindowIds = new Set(journal.plan?.recovery?.windowIds || []);
  if (flags['dry-run']) {
    const current = await discover();
    if (current.unavailable) throw new Error(current.message);
    const currentIds = new Set(current.windows.map((window) => window.id));
    return { dryRun: true, mutates: false, runId, snapshotId: current.snapshotId, windowIds: [...recoverableWindowIds].filter((id) => currentIds.has(id)), missingWindowIds: [...recoverableWindowIds].filter((id) => !currentIds.has(id)) };
  }
  const recoveryId = `${runId}-recovery`;
  const releaseLock = await acquireLock(recoveryId);
  const result = { runId, recoveryId, restored: [], skipped: [], failed: [] };
  try {
    const current = await discover();
    if (current.unavailable) throw new Error(current.message);
    const currentSpacesByUuid = new Map(current.spaces.map((space) => [space.uuid, space]));
    const beforeSpacesByIndex = new Map(journal.before.spaces.map((space) => [space.index, space]));
    const currentWindows = new Map(current.windows.map((window) => [window.id, window]));
    for (const window of journal.before.windows.filter((item) => recoverableWindowIds.has(item.id))) {
      if (!currentWindows.has(window.id)) { result.skipped.push({ windowId: window.id, reason: 'window no longer exists' }); continue; }
      const beforeSpace = beforeSpacesByIndex.get(window.space);
      const targetSpace = beforeSpace ? currentSpacesByUuid.get(beforeSpace.uuid) : null;
      if (!targetSpace) { result.skipped.push({ windowId: window.id, reason: 'original Space no longer exists' }); continue; }
      try {
        await execFileAsync('yabai', ['-m', 'window', String(window.id), '--space', String(targetSpace.index)], { timeout: 3000 });
        if (window.movable) await execFileAsync('yabai', ['-m', 'window', String(window.id), '--move', `abs:${Math.round(window.frame.x)}:${Math.round(window.frame.y)}`], { timeout: 3000 });
        if (window.resizable) await execFileAsync('yabai', ['-m', 'window', String(window.id), '--resize', `abs:${Math.round(window.frame.w)}:${Math.round(window.frame.h)}`], { timeout: 3000 });
        result.restored.push(window.id);
      } catch (error) { result.failed.push({ windowId: window.id, error: error.message }); }
    }
    await atomicWrite(join(stateRoot, 'runs', `${recoveryId}.json`), { formatVersion: 1, status: result.failed.length ? 'partial' : 'completed', createdAt: new Date().toISOString(), result });
    return result;
  } finally { await releaseLock(); }
}

async function main() {
  if (command === 'inspect') {
    const snapshot = await discover();
    flags.json ? print(snapshot) : printInspect(snapshot);
    if (snapshot.unavailable) process.exitCode = 1;
    return;
  }
  if (command === 'plan' || command === 'verify') {
    const result = await livePlan();
    if (flags.json) print(command === 'plan' ? { snapshot: result.snapshot, desired: result.desired, comparison: result.comparison, plan: result.plan } : result.comparison);
    else if (command === 'plan') printPlan(result.plan, result.comparison);
    else console.log(`${result.comparison.converged ? 'OK' : 'DRIFT'}    ${summarizeComparison(result.comparison)}`);
    if (command === 'verify' && !result.comparison.converged) process.exitCode = 1;
    if (command === 'plan' && !result.plan.executable) process.exitCode = 1;
    return;
  }
  if (command === 'capture') {
    const snapshot = await discover();
    if (snapshot.unavailable) throw new Error(snapshot.message);
    print(captureWorkspace(snapshot, { workspaceId: positional[0], mode: positional[1] || flags.mode || 'wide', spaceIndex: flags['space-index'], spaceUuid: flags['space-uuid'], name: flags.name, spaceLabel: flags.label }));
    return;
  }
  if (command === 'event') {
    const event = positional[0];
    if (event !== 'wake') throw new Error('event must be “wake”');
    const session = await readJson(join(stateRoot, 'configurator.json'), null);
    if (!Number.isInteger(session?.pid)) throw new Error('the configurator service is not running; start “spacewright configure” first');
    try { process.kill(session.pid, 0); } catch { throw new Error('the saved configurator session is stale; restart “spacewright configure”'); }
    const { stdout: processCommand } = await execFileAsync('ps', ['-p', String(session.pid), '-o', 'command='], { timeout: 2000 });
    if (!processCommand.includes('configurator/server.mjs')) throw new Error('the saved configurator PID belongs to another process; restart “spacewright configure”');
    if (flags['dry-run']) { console.log(`dry_run=event\nevent=${event}\npid=${session.pid}`); return; }
    process.kill(session.pid, 'SIGUSR1');
    console.log(`OK      ${event} event delivered to configurator pid ${session.pid}`);
    return;
  }
  if (command === 'apply') {
    const target = parseTarget();
    if (flags['dry-run']) {
      const result = await livePlan(target);
      flags.json ? print({ dryRun: true, mutates: false, snapshot: result.snapshot, desired: result.desired, comparison: result.comparison, plan: result.plan }) : printPlan(result.plan, result.comparison);
      if (!result.plan.executable) process.exitCode = 1;
      return;
    }
    const result = await applyPlan(target);
    const label = result.status === 'completed' ? 'OK' : result.status === 'stale' ? 'STALE' : 'FAIL';
    flags.json ? print(result) : console.log(result.noop ? 'OK      target is already converged' : `${label}    run=${result.runId} journal=${result.journal}`);
    if (!result.noop && result.status !== 'completed') process.exitCode = 1;
    return;
  }
  if (command === 'recover') {
    const result = await restoreRun(positional[0]);
    flags.json ? print(result) : console.log(result.dryRun ? `DRY RUN window candidates=${result.windowIds.length} missing=${result.missingWindowIds.length}` : `${result.failed.length ? 'PARTIAL' : 'OK'}    restored=${result.restored.length} skipped=${result.skipped.length} failed=${result.failed.length}`);
    if (!result.dryRun && result.failed.length) process.exitCode = 1;
    return;
  }
  console.log([
    'usage: state-cli.mjs <command>', '',
    'commands:',
    '  inspect [--json]                         discover displays, Spaces, and windows',
    '  plan <workspace> <mode> [--json]         compare live state and print an exact plan',
    '  plan <solo|wide|tall> [--json]           plan an aggregate mode',
    '  verify <target> [mode] [--json]          return nonzero while drift remains',
    '  capture [id] [mode] [--space-index=N]    print an unsaved workspace draft',
    '  event wake [--dry-run]                   deliver a wake event to the configurator',
    '  apply <target> [mode] [--dry-run]        execute, verify, and journal a plan',
    '  recover <run-id> [--dry-run]             best-effort restore window Spaces and frames'
  ].join('\n'));
}

main().catch((error) => { console.error(`spacewright: ${error.message}`); process.exitCode = 1; });
