#!/usr/bin/env node

import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { existsSync } from 'node:fs';
import { readFile, rm } from 'node:fs/promises';
import { dirname, join, resolve } from 'node:path';
import { randomBytes } from 'node:crypto';
import { fileURLToPath } from 'node:url';
import { buildDesiredState, buildExecutionPlan, captureWorkspace, compareState, summarizeComparison } from './lib/state-engine.mjs';
import { compileV2, validateV2 } from './lib/config-v2.mjs';
import { resolveV3, validateV3 } from './lib/config-v3.mjs';
import { restoreWindow, sameWindowIdentity,recoveryCandidates } from './lib/recovery.mjs';
import { stableRead } from './lib/config-store.mjs';
import { discoverState } from './lib/discovery.mjs';
import { acquireExecution, runBounded, sleep } from './lib/execution-coordinator.mjs';
import { durableJson, operationRecords } from './lib/operation-journal.mjs';
import { consumeBudget } from './lib/execution-budget.mjs';
import { detectMacHardware } from './lib/hardware-detection.mjs';
import { readSpaceLabelHints } from './lib/space-label-history.mjs';
import { executionCensus } from './lib/window-policy.mjs';

const execFileAsync = promisify(execFile);
const command = process.argv[2] || 'help';
const positional = process.argv.slice(3).filter((value) => !value.startsWith('--'));
const flags = Object.fromEntries(process.argv.slice(3).filter((value) => value.startsWith('--')).map((value) => {
  const [key, ...rest] = value.slice(2).split('=');
  return [key, rest.length ? rest.join('=') : true];
}));
const packageRoot = resolve(flags['package-root'] || join(dirname(fileURLToPath(import.meta.url)), '..'));
const configRoot = resolve(flags['config-root'] || process.env.SPACEWRIGHT_CONFIG_ROOT || join(process.env.HOME, '.config', 'spacewright'));
const stateRoot = resolve(flags['state-root'] || process.env.SPACEWRIGHT_STATE_ROOT || join(process.env.HOME, '.local', 'state', 'spacewright'));
const v2ConfigFile = join(configRoot, 'config.v2.json');
const v3ConfigFile = join(configRoot, 'config.v3.json');
const machineFile = join(stateRoot, 'machine.json');
const executable = join(packageRoot, 'bin', 'spacewright');

async function readJson(path, fallback) {
  if (!existsSync(path)) return structuredClone(fallback);
  return JSON.parse(await readFile(path, 'utf8'));
}

async function atomicWrite(path, value) {
  await durableJson(path,value);
}

export async function discover(machineOverride = null, { deadline = executionDeadline } = {}) {
  return discoverState(machineOverride || await readJson(machineFile, { version: 1, displayBindings: {} }), { deadline: Math.min(deadline, executionDeadline), signal: cancellation.signal });
}

async function context() {
  const configFile = existsSync(v3ConfigFile) ? v3ConfigFile : v2ConfigFile;
  if (!existsSync(configFile)) throw new Error(`portable configuration not found under ${configRoot}; run “spacewright configure” first`);
  const { config: portableConfig, machine, source } = await stableRead(configFile, machineFile);
  const snapshot = await discover(machine);
  const validation = portableConfig.version === 3 ? validateV3(portableConfig) : validateV2(portableConfig);
  if (!validation.valid) throw new Error(`configuration is invalid:\n${validation.errors.join('\n')}`);
  if (portableConfig.version === 3) {
    const hardware = await detectMacHardware({deadline:executionDeadline,signal:cancellation.signal});
    const resolution = resolveV3(portableConfig, { machine, hardware, snapshot });
    return { config: resolution.v2, portableConfig, configFile, source, machine, snapshot, resolution, runtime: compileV2(resolution.v2) };
  }
  return { config: portableConfig, portableConfig, configFile, source, machine, snapshot, resolution: null, runtime: compileV2(portableConfig) };
}

function parseTarget(values = positional) {
  if (flags.profile) return { kind: 'profile', id: String(flags.profile) };
  const id = values[0];
  const mode = values[1];
  if (!id) throw new Error('target is required; use a workspace id plus mode, a mode name, or --profile=<id>');
  if (['solo', 'wide', 'tall'].includes(id) && !mode) return { kind: 'mode', id, mode: id };
  return { kind: 'workspace', id, mode };
}

async function livePlan(target = parseTarget(), frozen = null, snapshot = null) {
  const value = frozen ? { ...frozen, snapshot: snapshot || await discover(frozen.machine) } : await context();
  const normalizedTarget = value.resolution && target.kind === 'workspace' && !target.mode
    ? { ...target, mode: value.config.modes[value.portableConfig.hardwareProfiles[value.resolution.hardwareProfileId].setups[value.resolution.setupId].compatibilityMode] ? value.portableConfig.hardwareProfiles[value.resolution.hardwareProfileId].setups[value.resolution.setupId].compatibilityMode : null }
    : target;
  const desired = buildDesiredState(value.config, value.runtime, normalizedTarget, value.snapshot);
  const spaceLabelHints = await readSpaceLabelHints(stateRoot, desired, value.snapshot);
  const comparison = compareState(value.snapshot, desired, value.machine, { spaceLabelHints });
  const plan = buildExecutionPlan(value.snapshot, desired, comparison, { displayPrepared: value.displayPrepared });
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

let executionLease = null;
async function acquireLock(runId) {
  const portableFile=existsSync(v3ConfigFile)?v3ConfigFile:v2ConfigFile;
  const budgets=existsSync(portableFile)?(await stableRead(portableFile,machineFile)).config.settings?.executionBudgets:undefined;
  executionLease = await acquireExecution(stateRoot, { runId, controller: 'state-cli', budgets, deadlineAt: new Date(executionDeadline).toISOString() });
  executionDeadline=Math.min(executionDeadline,new Date(executionLease.owner.deadlineAt).getTime());
  return executionLease.release;
}
async function runCommand(args, journal, journalFile, plannedStep, attempt = 0) {
  assertNotCancelled();
  const step = { ...plannedStep, attempt, status: 'running', command: ['spacewright', ...args], startedAt: new Date().toISOString() };
  journal.steps.push(step);
  if (plannedStep.action === 'display_profile') journal.effects.push({type:'display_profile',profile:args[1],attempted:true,reversible:false});
  await atomicWrite(journalFile, journal);
  const outputBuffers = {stdout:'',stderr:''};
  try {
    const result = await runBounded(executable, args, { deadline: executionDeadline, signal: cancellation.signal,
      env: { ...process.env, ...executionLease.env, SPACEWRIGHT_CONFIG_ROOT: configRoot, SPACEWRIGHT_STATE_ROOT: stateRoot,
        SPACEWRIGHT_EXECUTION_CONFIG: journal.effectiveConfigFile, SPACEWRIGHT_EXECUTION_ENVELOPE: journal.envelopeFile,
        SPACEWRIGHT_OPERATION_RUN_ID:journal.runId,
        SPACEWRIGHT_RUNTIME_GENERATION: journal.plan?.configDigest, WORKSPACE_DISABLE_YABAI_AUTO_RESTART: '1', WORKSPACE_SKIP_FINALIZATION: '1' },
      onChild: async (child) => { activeChild = child; await executionLease.trackChild(child); },
      onOutput: (stream, value) => {
        for (const line of value.split('\n').filter(Boolean)) journal.logs.push({ timestamp: new Date().toISOString(), stream, line });
        {
          outputBuffers[stream] += value;
          const lines = outputBuffers[stream].split('\n'); outputBuffers[stream] = lines.pop();
          for (const line of lines.filter((l) => l.startsWith('[MUTATION] '))) try { journal.effects.push(JSON.parse(line.slice(11))); } catch {}
        }
      }
    });
    step.status = result.code === 0 ? 'completed' : result.code === 124 ? 'timed_out' : result.code === 130 ? 'cancelled' : 'failed'; step.exitCode = result.code;
    return result.code;
  } catch (error) { step.status = error.code === 'SPACEWRIGHT_CANCELLED' ? 'cancelled' : error.code === 'SPACEWRIGHT_TIMEOUT' ? 'timed_out' : 'failed'; step.error = error.message; throw error; }
  finally {
    step.finishedAt = new Date().toISOString();
    journal.operations=await operationRecords(stateRoot,journal.runId);
    const operations=journal.operations.filter(r=>r.id);
    journal.effects=[...journal.effects.filter(e=>!operations.some(r=>r.windowId===e.windowId && r.type===e.type)),...operations];
    await atomicWrite(journalFile,journal);
  }
}

async function waitForDesktopStateToSettle(executionSteps) {
  if (executionSteps.some((step) => step.action === 'focus')) {
    await new Promise((resolveWait) => setTimeout(resolveWait, 500));
  }
}

let activeChild = null;
let cancellationSignal = null;
const cancellation = new AbortController();
let executionDeadline = Number(process.env.SPACEWRIGHT_EXECUTION_DEADLINE_MS) || Date.now() + Number(flags['timeout-seconds'] || 120) * 1000;
function cancellationError() { return Object.assign(new Error(`operation cancelled by ${cancellationSignal || 'signal'}`), { code: 'SPACEWRIGHT_CANCELLED' }); }
function assertNotCancelled() {
  if (cancellationSignal) throw cancellationError();
  if (Date.now() >= executionDeadline) throw Object.assign(new Error('execution deadline exceeded'), { code: 'SPACEWRIGHT_TIMEOUT' });
}
for (const signal of ['SIGINT', 'SIGTERM']) process.on(signal, () => {
  cancellationSignal ||= signal;
  cancellation.abort(cancellationError());
  if(executionLease)void executionLease.cancel().catch(error=>process.stderr.write(`cancellation state write failed: ${error.message}\n`));
});

async function assertSavedConfiguration(initial) {
  assertNotCancelled();
  if ((existsSync(v3ConfigFile) ? v3ConfigFile : v2ConfigFile) !== initial.configFile) throw new Error('active configuration changed during execution; replan required');
  const currentConfig = await stableRead(initial.configFile, machineFile);
  if (currentConfig.source !== initial.source) throw new Error('configuration changed during execution; replan required');
  if(JSON.stringify(currentConfig.machine)!==JSON.stringify(initial.machine))throw new Error('machine generation changed during execution; replan required');
  const roles = new Set(initial.desired.workspaces.map((w) => w.displayRole));
  for (const role of roles) if (currentConfig.machine.displayBindings?.[role] !== initial.machine.displayBindings?.[role]) throw new Error('machine display bindings changed; replan required');
}

async function assertExecutionContext(initial,effects = []) {
  await assertSavedConfiguration(initial);
  const snapshot = await discover(initial.machine);
  if (snapshot.completeness !== 'complete') throw new Error(snapshot.message);
  if(initial.plan.scope==='mode' && JSON.stringify(executionCensus(snapshot.windows,initial.plan.selectedWindows).map(w=>w.id))!==JSON.stringify(initial.plan.preconditions.windows.map(w=>w.id)))throw new Error('global object census changed; replan required');
  const spaceLabelHints=Object.fromEntries(initial.plan.workspaces.filter(w=>w.targetSpace?.uuid).map(w=>[w.label,w.targetSpace.uuid]));
  const comparison = compareState(snapshot, initial.desired, initial.machine, {spaceLabelHints});
  if(comparison.counts.blocker)throw new Error(`execution preconditions changed: ${comparison.drifts.filter(d=>d.severity==='blocker').map(d=>d.code).join(', ')}; replan required`);
  const currentPlan = buildExecutionPlan(snapshot, initial.desired, comparison);
  if (JSON.stringify(currentPlan.selectedWindows) !== JSON.stringify(initial.plan.selectedWindows)) throw new Error('planned windows or ownership changed; replan required');
  for (const original of initial.plan.workspaces) {
    if (!original.targetSpace && snapshot.spaces.some((s)=>s.label===original.label) && !effects.some((e)=>e.type==='ensure_space' && e.workspaceId===original.workspaceId)) throw new Error('target Space appeared after planning; replan required');
    if (original.targetSpace?.uuid) {
      const currentSpace = snapshot.spaces.find((s) => s.uuid === original.targetSpace.uuid);
      if (!currentSpace || ![original.targetSpace.label,original.label].includes(currentSpace.label)) throw new Error('planned Space disappeared or its label changed; replan required');
    }
    const beforeDisplay = initial.snapshot.displays.find((d) => d.role === original.displayRole);
    if (beforeDisplay && !snapshot.displays.some((d) => d.uuid === beforeDisplay.uuid && JSON.stringify(d.frame) === JSON.stringify(beforeDisplay.frame))) throw new Error('relevant display changed; replan required');
  }
}

// A display command may change geometry, but cannot authorize a new set of
// physical displays, Spaces, windows, owners or workspaces.
function assertDisplayPhaseContinuity(initial, next) {
  if (JSON.stringify(next.plan.selectedWindows) !== JSON.stringify(initial.plan.selectedWindows)) throw new Error('planned windows or ownership changed during display preparation');
  const physical = snapshot => snapshot.displays.map(d => ({ uuid: d.uuid, builtIn: d.builtIn })).sort((a,b) => a.uuid.localeCompare(b.uuid));
  if (JSON.stringify(physical(initial.snapshot)) !== JSON.stringify(physical(next.snapshot))) throw new Error('physical display identities changed during display preparation');
  const spaceIdentity = (space, snapshot) => ({ uuid: space.uuid, label: space.label, layout: space.layout,
    displayUuid: snapshot.displays.find(d => d.index === space.display)?.uuid });
  if (initial.plan.scope === 'mode' && JSON.stringify(initial.snapshot.spaces.map(s => s.uuid).sort()) !== JSON.stringify(next.snapshot.spaces.map(s => s.uuid).sort())) throw new Error('Space census changed during display preparation');
  for (const original of initial.plan.preconditions.spaces) {
    const current = next.snapshot.spaces.find(s => s.uuid === original.uuid);
    if (!current || JSON.stringify(spaceIdentity(original, initial.snapshot)) !== JSON.stringify(spaceIdentity(current, next.snapshot))) throw new Error('planned Space disappeared or changed during display preparation');
  }
  for (const original of initial.plan.workspaces) {
    const current = next.plan.workspaces.find(w => w.workspaceId === original.workspaceId);
    if (!current || current.targetSpace?.uuid !== original.targetSpace?.uuid || current.targetDisplay?.uuid !== original.targetDisplay?.uuid) throw new Error('planned Space or target display changed during display preparation');
  }
  const census = value => value.plan.preconditions.windows.map(w => ({ id: w.id, app: w.app, pid: w.pid,
    processFingerprint: w.processFingerprint, bundleId: w.bundleId, movable: w.movable, resizable: w.resizable,
    minimized: w.minimized, nativeFullscreen: w.nativeFullscreen,
    spaceUuid: value.snapshot.spaces.find(s => s.index === w.space)?.uuid,
    displayUuid: value.snapshot.displays.find(d => d.index === w.display)?.uuid })).sort((a,b) => a.id-b.id);
  if (JSON.stringify(census(initial)) !== JSON.stringify(census(next))) throw new Error('window census or ownership changed during display preparation');
  if (JSON.stringify(initial.desired.workspaces) !== JSON.stringify(next.desired.workspaces)
    || JSON.stringify(initial.desired.contextualApps) !== JSON.stringify(next.desired.contextualApps)
    || next.plan.configDigest !== initial.plan.configDigest) throw new Error('execution scope changed during display preparation');
}

async function replanAfterDisplay(initial, target) {
  const deadline = Math.min(executionDeadline, Date.now() + 5000);
  let previous = null, stableSamples = 0;
  while (Date.now() < deadline) {
    await assertSavedConfiguration(initial);
    const snapshot = await discover(initial.machine, { deadline });
    assertNotCancelled();
    if (snapshot.completeness !== 'complete') throw new Error(snapshot.message);
    const signature = JSON.stringify(snapshot.displays.map(d => ({ uuid:d.uuid,index:d.index,frame:d.frame,gridGeometry:d.gridGeometry,builtIn:d.builtIn })).sort((a,b) => a.uuid.localeCompare(b.uuid)));
    stableSamples = signature === previous ? stableSamples + 1 : 1;
    previous = signature;
    const next = await livePlan(target, { ...initial, displayPrepared: true }, snapshot);
    assertDisplayPhaseContinuity(initial, next);
    if (!next.plan.executable) throw new Error(`layout after display preparation is blocked: ${next.plan.blockers.map(b => b.code).join(', ')}`);
    if (stableSamples >= Math.max(2, initial.config.settings?.topologyStableSamples || 3)) {
      if (initial.resolution) {
        const hardware = await detectMacHardware({ deadline, signal: cancellation.signal });
        const resolution = resolveV3(initial.portableConfig, { machine: initial.machine, hardware, snapshot });
        if (resolution.hardwareProfileId !== initial.resolution.hardwareProfileId || resolution.setupId !== initial.resolution.setupId) throw new Error('hardware setup changed during display preparation; confirmation required');
      }
      await assertSavedConfiguration(initial);
      return next;
    }
    await sleep(Math.min(150, Math.max(0, deadline - Date.now())));
  }
  throw Object.assign(new Error('display state did not stabilize before the preparation deadline'), { code: 'SPACEWRIGHT_TIMEOUT' });
}

async function applyPlan(target) {
  const runId = `${Date.now()}-${randomBytes(4).toString('hex')}`;
  const releaseLock = await acquireLock(runId);
  const journalFile = join(stateRoot,'runs',`${runId}.json`);
  let journal = {formatVersion:2,runId,status:'preflight',createdAt:new Date().toISOString(),target,steps:[],logs:[],effects:[],exitCode:0};
  try {
    await executionLease.trackJournal(journalFile);
    await atomicWrite(journalFile,journal);
    assertNotCancelled();
    let initial = await livePlan(target);
    assertNotCancelled();
    journal.plan=initial.plan;
    journal.before=initial.snapshot;
    journal.comparison=initial.comparison;
    await atomicWrite(journalFile,journal);
    if (initial.snapshot.completeness !== 'complete') throw new Error(initial.snapshot.message);
    const expected = {
      planId: flags['expected-plan-id'],
      configDigest: flags['expected-config-digest'],
      snapshotId: flags['expected-snapshot-id']
    };
    if ((expected.planId && expected.planId !== initial.plan.planId)
      || (expected.configDigest && expected.configDigest !== initial.plan.configDigest)
      || (!expected.planId && expected.snapshotId && expected.snapshotId !== initial.snapshot.snapshotId)) {
      journal.status='stale';journal.exitCode=75;journal.finishedAt=new Date().toISOString();journal.plan=initial.plan;
      await atomicWrite(journalFile,journal);
      return { stale: true, status: 'stale', exitCode: 75, expected, actual: { planId: initial.plan.planId, configDigest: initial.plan.configDigest, snapshotId: initial.snapshot.snapshotId }, plan: initial.plan, comparison: initial.comparison };
    }
    if (!initial.plan.executable) throw new Error(`plan ${initial.plan.planId} is blocked: ${initial.plan.blockers.map((item) => item.code).join(', ')}`);
    if (!initial.plan.actions.length) {
      journal.status='completed';journal.finishedAt=new Date().toISOString();journal.plan=initial.plan;journal.after=initial.snapshot;journal.verification=initial.comparison;
      await atomicWrite(journalFile,journal);
      return { noop: true, plan: initial.plan, comparison: initial.comparison };
    }
    journal = {
      formatVersion: 2,
      runId,
      status: 'preflight',
      createdAt: new Date().toISOString(),
      target: initial.plan.target,
      plan: initial.plan,
      before: initial.snapshot,
      steps: [],
      logs: [],
      exitCode: 0,
      effects: [],
      effectiveConfigFile: join(stateRoot, 'execution-context', `${runId}.runtime.json`),
      envelopeFile: join(stateRoot, 'execution-context', `${runId}.envelope.json`)
    };
    await atomicWrite(journal.effectiveConfigFile, initial.runtime);
    await atomicWrite(journal.envelopeFile, { plan: initial.plan, desired: initial.desired, machine: initial.machine });
    await executionLease.trackJournal(journalFile);
    await atomicWrite(journalFile, journal);
    const preflight = await livePlan(target);
    assertNotCancelled();
    if (preflight.plan.configDigest !== initial.plan.configDigest || preflight.plan.preconditionDigest !== initial.plan.preconditionDigest || preflight.plan.planId !== initial.plan.planId) {
      journal.status = 'stale'; journal.exitCode = 75; journal.finishedAt = new Date().toISOString();
      journal.preflight = { snapshotId: preflight.snapshot.snapshotId, planId: preflight.plan.planId, configDigest: preflight.plan.configDigest };
      journal.logs.push({ timestamp: journal.finishedAt, stream: 'system', line: 'preflight state changed after planning; no mutation was attempted' });
      await atomicWrite(journalFile, journal);
      return { runId, status: journal.status, exitCode: journal.exitCode, plan: initial.plan, journal: journalFile, stale: journal.preflight };
    }
    journal.status = 'running';
    await atomicWrite(journalFile, journal);
    const displayStep = initial.plan.executionSteps.find(step => step.action === 'display_profile');
    if (displayStep) {
      await assertExecutionContext(initial, journal.effects);
      journal.displayPlan = initial.plan;
      journal.exitCode = await runCommand(displayStep.command, journal, journalFile, displayStep);
      assertNotCancelled();
      if (journal.exitCode !== 0) throw Object.assign(new Error(`display preparation command failed (${journal.exitCode}); layout was not attempted`), { code: journal.exitCode === 124 ? 'SPACEWRIGHT_TIMEOUT' : journal.exitCode === 130 ? 'SPACEWRIGHT_CANCELLED' : undefined });
      const next = await replanAfterDisplay(initial, target);
      (journal.planRelations ||= []).push({ phase:'display',fromPlanId:initial.plan.planId,toPlanId:next.plan.planId,beforeSnapshotId:initial.snapshot.snapshotId,afterSnapshotId:next.snapshot.snapshotId });
      initial = next; journal.plan = next.plan; journal.layoutBefore = next.snapshot;
      await atomicWrite(journal.envelopeFile, { plan:next.plan,desired:next.desired,machine:next.machine });
      await atomicWrite(journalFile, journal);
    }
    for(let phase=0;initial.plan.preparations.length;phase++) {
      if(phase>=2)throw new Error('adapter preparation did not satisfy layout prerequisites');
      journal.preparationPlan ||= initial.plan;
      (journal.preparationPlans ||= []).push(initial.plan);
      const observing=initial.plan.preparations.some(p=>p.type==='observe_space');
      journal.exitCode=await runCommand(['prepare-adapters'],journal,journalFile,{type:'preparation',action:'prepare_adapters',planId:initial.plan.planId});
      assertNotCancelled();
      if(journal.exitCode!==0)throw Object.assign(new Error('explicit adapter preparation failed; layout was not attempted'),{code:journal.exitCode===124?'SPACEWRIGHT_TIMEOUT':journal.exitCode===130?'SPACEWRIGHT_CANCELLED':undefined});
      const saved=await stableRead(initial.configFile,machineFile);
      if(saved.source!==initial.source || JSON.stringify(saved.machine)!==JSON.stringify(initial.machine))throw new Error('configuration changed during preparation; replan required');
      const next=await livePlan(target,initial);
      if(!next.plan.executable || next.plan.preparations.length && (!observing || next.plan.preparations.some(p=>p.type==='observe_space')))throw new Error('adapter preparation did not satisfy layout prerequisites');
      (journal.planRelations ||= []).push({phase:'preparation',fromPlanId:initial.plan.planId,toPlanId:next.plan.planId,before:initial.plan.selectedWindows,after:next.plan.selectedWindows});
      initial=next;journal.plan=next.plan;journal.layoutBefore=next.snapshot;
      await atomicWrite(journal.envelopeFile,{plan:next.plan,desired:next.desired,machine:next.machine});
      await atomicWrite(journalFile,journal);
    }
    for (const step of initial.plan.executionSteps) {
      assertNotCancelled();
      await assertExecutionContext(initial,journal.effects);
      journal.exitCode = await runCommand(step.command, journal, journalFile, step, 0);
      await atomicWrite(journalFile, journal);
      assertNotCancelled();
      if (journal.exitCode !== 0) break;
    }
    if (journal.exitCode === 0) await waitForDesktopStateToSettle(initial.plan.executionSteps);
    assertNotCancelled();
    let verification = await livePlan(target, initial);
    assertNotCancelled();
    journal.after = verification.snapshot;
    journal.verification = verification.comparison;
    if (journal.exitCode === 0 && JSON.stringify(verification.plan.selectedWindows) === JSON.stringify(initial.plan.selectedWindows) && !verification.comparison.converged && verification.plan.executable && verification.plan.actions.length && initial.plan.recovery.automaticAttempts > 0 && !flags['no-reconcile']) {
      await consumeBudget(stateRoot,'reconciliation',{env:executionLease.env});
      journal.steps.push({ type: 'reconciliation', status: 'started', startedAt: new Date().toISOString(), remaining: verification.comparison.counts, planId: verification.plan.planId });
      await atomicWrite(journalFile, journal);
      await atomicWrite(journal.envelopeFile, { plan: verification.plan, desired: initial.desired, machine: initial.machine });
      for (const step of verification.plan.executionSteps) {
        assertNotCancelled();
        await assertExecutionContext(initial,journal.effects);
        journal.exitCode = await runCommand(step.command, journal, journalFile, step, 1);
        await atomicWrite(journalFile, journal);
        assertNotCancelled();
        if (journal.exitCode !== 0) break;
      }
      if (journal.exitCode === 0) await waitForDesktopStateToSettle(verification.plan.executionSteps);
      verification = await livePlan(target, initial);
      journal.after = verification.snapshot;
      journal.verification = verification.comparison;
    }
    journal.status = journal.exitCode === 0 && journal.verification.converged && JSON.stringify(verification.plan.selectedWindows) === JSON.stringify(initial.plan.selectedWindows) ? 'completed' : 'failed';
    if (journal.status === 'failed' && journal.exitCode === 0) journal.exitCode = 1;
    journal.finishedAt = new Date().toISOString();
    await atomicWrite(journalFile, journal);
    return { runId, status: journal.status, exitCode: journal.exitCode, plan: initial.plan, verification: journal.verification, journal: journalFile };
  } catch (error) {
    const status = error.code === 'SPACEWRIGHT_CANCELLED' ? 'cancelled' : error.code === 'SPACEWRIGHT_TIMEOUT' ? 'timed_out' : 'failed';
    const exitCode = status === 'cancelled' ? 130 : status === 'timed_out' ? 124 : 1;
    if (journal && journalFile) {
      const interruptedStep = [...journal.steps].reverse().find((step) => step.status === 'running');
      if (interruptedStep) interruptedStep.status = status;
      journal.status = status; journal.exitCode = exitCode; journal.finishedAt = new Date().toISOString(); journal.error = error.message;
      journal.logs.push({ timestamp: journal.finishedAt, stream: 'system', line: error.message });
      try { await atomicWrite(journalFile, journal); }
      catch (writeError) { process.stderr.write(`terminal journal write failed: ${writeError.message}; run=${runId} status=${status}\n`); }
    }
    if (status === 'failed' && !journal) throw error;
    return { runId, status, exitCode, error: error.message, journal: journalFile };

  } finally {
    await releaseLock();
    if (journal?.effectiveConfigFile) await rm(journal.effectiveConfigFile,{force:true});
    if (journal?.envelopeFile) await rm(journal.envelopeFile,{force:true});
  }
}

async function recoveryCommand(exe, args) {
  assertNotCancelled();
  const result = await runBounded(exe, args, { deadline: Math.min(executionDeadline, Date.now() + 3000), signal: cancellation.signal,
    onChild: async (child) => { activeChild = child; await executionLease.trackChild(child); } });
  if (result.code) throw new Error(result.stderr || `recovery command failed (${result.code})`);
}

async function restoreRun(runId) {
  if (!/^[0-9]+-[a-f0-9]{8}$/.test(runId)) throw new Error('invalid run id; expected the id printed by “spacewright apply”');
  const journalFile = join(stateRoot, 'runs', `${runId}.json`);
  const journal = await readJson(journalFile, null);
  if (!journal?.before) throw new Error(`run ${runId} has no recovery snapshot`);
  const candidates=recoveryCandidates(journal);
  const recoverableWindowIds = new Set(candidates.map(c=>c.window.id));
  if (flags['dry-run']) {
    const current = await discover();
    if (current.unavailable) throw new Error(current.message);
    const currentIds = new Set(candidates.filter(({window:w})=>sameWindowIdentity(w,current.windows.find(c=>c.id===w.id))).map(c=>c.window.id));
    return { dryRun: true, mutates: false, runId, snapshotId: current.snapshotId, windowIds: [...recoverableWindowIds].filter((id) => currentIds.has(id)), missingWindowIds: [...recoverableWindowIds].filter((id) => !currentIds.has(id)) };
  }
  const recoveryId = `${Date.now()}-${randomBytes(4).toString('hex')}`;
  const releaseLock = await acquireLock(recoveryId);
  const recoveryFile = join(stateRoot, 'runs', `${recoveryId}.json`);
  const result = { runId, recoveryId, status: 'running', restored: [], skipped: [], failed: [], nonrecoverable: (journal.effects || []).filter((e) => !e.windowId) };
  const recoveryJournal = { formatVersion: 2, runId: recoveryId, kind: 'recovery', sourceRunId: runId, status: 'running', createdAt: new Date().toISOString(), steps: [], result };
  try {
    assertNotCancelled();
    await executionLease.trackJournal(recoveryFile);
    await atomicWrite(recoveryFile, recoveryJournal);
    const current = await discover();
    assertNotCancelled();
    if (current.unavailable) throw new Error(current.message);
    const currentSpacesByUuid = new Map(current.spaces.map((space) => [space.uuid, space]));
    const currentWindows = new Map(current.windows.map((window) => [window.id, window]));
    for (const {window,spaceUuid} of candidates) {
      assertNotCancelled();
      const step = { windowId: window.id, status: 'running', startedAt: new Date().toISOString() };
      recoveryJournal.steps.push(step);
      await atomicWrite(recoveryFile, recoveryJournal);
      if (!currentWindows.has(window.id)) { step.status = 'skipped'; step.reason = 'window no longer exists'; result.skipped.push({ windowId: window.id, reason: step.reason }); await atomicWrite(recoveryFile, recoveryJournal); continue; }
      const liveWindow = currentWindows.get(window.id);
      if (!sameWindowIdentity(window,liveWindow)) {
        step.status = 'skipped'; step.reason = 'window identity changed'; result.skipped.push({ windowId: window.id, reason: step.reason }); continue;
      }
      const beforeSpace = {uuid:spaceUuid};
      const targetSpace = beforeSpace ? currentSpacesByUuid.get(beforeSpace.uuid) : null;
      if (!targetSpace) { step.status = 'skipped'; step.reason = 'original Space no longer exists'; result.skipped.push({ windowId: window.id, reason: step.reason }); await atomicWrite(recoveryFile, recoveryJournal); continue; }
      try {
        const restored = await restoreWindow(window, beforeSpace.uuid, { discover, run: recoveryCommand,
          beforeCommand: async (args) => { step.commands ||= []; step.commands.push({args,status:'attempted_unknown',identity:window,spaceUuid:beforeSpace.uuid}); await atomicWrite(recoveryFile,recoveryJournal); },
          afterCommand:async(args,verified)=>{const command=step.commands.at(-1);command.exitCode=0;command.status=verified?'verified_success':'failed';await atomicWrite(recoveryFile,recoveryJournal);} });
        step.attempted = restored.attempted;
        step.status = 'completed'; result.restored.push(window.id);
      } catch (error) {
        if (['SPACEWRIGHT_CANCELLED','SPACEWRIGHT_TIMEOUT'].includes(error.code)) throw error;
        if (error.code === 'SPACEWRIGHT_RECOVERY_SKIP') { step.status = 'skipped'; step.reason = error.message; result.skipped.push({windowId:window.id,reason:error.message}); continue; }
        step.status = 'failed'; step.error = error.message; result.failed.push({ windowId: window.id, error: error.message });
      }
      step.finishedAt = new Date().toISOString();
      await atomicWrite(recoveryFile, recoveryJournal);
    }
    result.status = result.failed.length || result.skipped.length ? (result.restored.length ? 'partial' : result.failed.length ? 'failed' : 'skipped') : 'completed';
    recoveryJournal.status = result.status; recoveryJournal.finishedAt = new Date().toISOString();
    await atomicWrite(recoveryFile, recoveryJournal);
    return result;
  } catch (error) {
    recoveryJournal.status = error.code === 'SPACEWRIGHT_CANCELLED' ? 'cancelled' : error.code === 'SPACEWRIGHT_TIMEOUT' ? 'timed_out' : 'failed';
    recoveryJournal.finishedAt = new Date().toISOString();
    recoveryJournal.error = error.message;
    const interruptedStep = [...recoveryJournal.steps].reverse().find((step) => step.status === 'running');
    if (interruptedStep) { interruptedStep.status = recoveryJournal.status; interruptedStep.finishedAt = recoveryJournal.finishedAt; }
    result.status = recoveryJournal.status;
    try{await atomicWrite(recoveryFile,recoveryJournal);}
    catch(writeError){process.stderr.write(`terminal recovery journal unavailable: ${writeError.message}; run=${recoveryId} status=${result.status} lastWindow=${interruptedStep?.windowId || 'none'}\n`);}
    if (['SPACEWRIGHT_CANCELLED','SPACEWRIGHT_TIMEOUT'].includes(error.code)) return result;
    throw error;
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
    if (flags['verified-marker'] && (result.noop || result.status === 'completed')) console.log('SPACEWRIGHT_VERIFIED');
    if (!result.noop && result.status !== 'completed') process.exitCode = result.exitCode || 1;
    return;
  }
  if (command === 'recover') {
    const result = await restoreRun(positional[0]);
    const label = result.status === 'completed' ? 'OK' : String(result.status || 'DRY RUN').toUpperCase();
    flags.json ? print(result) : console.log(result.dryRun ? `DRY RUN window candidates=${result.windowIds.length} missing=${result.missingWindowIds.length}` : `${label}    restored=${result.restored.length} skipped=${result.skipped.length} failed=${result.failed.length}`);
    if (!result.dryRun && result.status === 'cancelled') process.exitCode = 130;
    else if (!result.dryRun && result.status === 'timed_out') process.exitCode = 124;
    else if (!result.dryRun && result.status !== 'completed') process.exitCode = 1;
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
