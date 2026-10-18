#!/usr/bin/env node

import http from 'node:http';
import {mergeCapturedWorkspace} from './lib/capture-merge.mjs';
import { readFile, writeFile, rename, mkdir, copyFile, readdir, unlink, stat } from 'node:fs/promises';
import { existsSync } from 'node:fs';
import { basename, dirname, extname, join, resolve } from 'node:path';
import { randomBytes } from 'node:crypto';
import { createHash } from 'node:crypto';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { fileURLToPath } from 'node:url';
import YAML from 'yaml';
import { compileSkhd, compileV2, migrateV1, starterConfig, validateV2 } from './lib/config-v2.mjs';
import { compileV3, describeDisplays, matchingSetups, migrateV2ToV3, resolveV3, selectHardwareProfile, setupBindingStatus, starterV3, topologyKey, validateV3 } from './lib/config-v3.mjs';
import { detectMacHardware } from './lib/hardware-detection.mjs';
import { buildDesiredState, buildExecutionPlan, captureWorkspace, compareState } from './lib/state-engine.mjs';
import { generationDocument, verifyRuntimeDocument, withConfigurationWrite, stableRead,atomicText, hash } from './lib/config-store.mjs';
import { discoverState } from './lib/discovery.mjs';
import { classifyTopology, matchingRules, ruleContext } from './lib/automation-policy.mjs';
import { runWebTask, cancelWebTask } from './lib/task-coordinator.mjs';
import { AsyncLocalStorage } from 'node:async_hooks';
import { createAutomationMonitor } from './lib/automation-monitor.mjs';
import { clearTransitionHistory, readTransitionHistory } from './lib/transition-history.mjs';
import { readSpaceLabelHints } from './lib/space-label-history.mjs';

const execFileAsync = promisify(execFile);
const args = Object.fromEntries(process.argv.slice(2).map((arg) => arg.split('=', 2)));
const packageRoot = resolve(args['--package-root'] || join(dirname(fileURLToPath(import.meta.url)), '..'));
const configRoot = resolve(args['--config-root'] || join(process.env.HOME, '.config', 'spacewright'));
const stateRoot = resolve(args['--state-root'] || join(process.env.HOME, '.local', 'state', 'spacewright'));
const configFile = join(configRoot, 'config.v2.json');
const configV3File = join(configRoot, 'config.v3.json');
const skhdFile = resolve(args['--skhd-file'] || join(process.env.HOME, '.config', 'skhd', 'skhdrc'));
const machineFile = join(stateRoot, 'machine.json');
const runtimeFile = join(configRoot, 'generated', 'runtime.json');
const historyRoot = join(stateRoot, 'history');
const activityFile = join(stateRoot, 'activity.jsonl');
const sessionFile = join(stateRoot, 'configurator.json');
const publicRoot = join(packageRoot, 'configurator', 'public');
const token = args['--token'] || randomBytes(24).toString('hex');
const listenPort = Number(args['--port'] || 0);
const initialView = args['--view'];
if (initialView && !['current', 'hardware', 'map', 'displays', 'workspaces', 'apps', 'shortcuts', 'automation', 'history', 'diagnostics', 'tasks', 'review'].includes(initialView)) throw new Error('unknown configurator view');
const tasks = new Map();
const captures = new Map();
const MAX_TASKS = 100;
const MAX_TASK_LOG_LINES = 2000;
const unsavedStarterConfig = starterConfig();
let taskQueue = Promise.resolve();
let closing=false;
let configWriteQueue = Promise.resolve();
const configurationScope = new AsyncLocalStorage();

function serializeConfigWrite(operation) {
  const guarded = async () => {
    const scope={responses:[]};
    const result=await withConfigurationWrite(configRoot,transaction=>configurationScope.run({...scope,transaction},operation),{trackWrites:true});
    for(const respond of scope.responses)respond();
    return result;
  };
  const queued = configWriteQueue.then(guarded, guarded);
  configWriteQueue = queued.catch(() => {});
  return queued;
}

async function readConfig() {
  if (!existsSync(configFile)) return structuredClone(unsavedStarterConfig);
  return (await stableRead(configFile, machineFile, {ownedWrite:Boolean(configurationScope.getStore())})).config;
}

async function readOperationalConfig() {
  if (existsSync(configV3File) || existsSync(configFile)) return (await activeDocument()).config;
  return readConfig();
}

async function readLegacyConfig() {
  const defaults = JSON.parse(await readFile(join(packageRoot, 'config', 'defaults.json'), 'utf8'));
  const userFile = join(configRoot, 'config.json');
  if (!existsSync(userFile)) return defaults;
  const user = JSON.parse(await readFile(userFile, 'utf8'));
  const merge = (base, override) => {
    if (!base || !override || typeof base !== 'object' || typeof override !== 'object' || Array.isArray(base) || Array.isArray(override)) return override;
    const result = { ...base };
    for (const [key, value] of Object.entries(override)) result[key] = key in base ? merge(base[key], value) : value;
    return result;
  };
  return merge(defaults, user);
}

async function readMachine() {
  const selected=existsSync(configV3File)?configV3File:configFile;
  const {machine:value}=await stableRead(selected,machineFile,{ownedWrite:Boolean(configurationScope.getStore()),allowMissingConfig:true});
  return normalizedMachine(value);
}

function normalizedMachine(value) {
  return { ...value, version: value.version || 1, displayBindings: value.displayBindings || {} };
}

function json(response, status, body) {
  const serialized=JSON.stringify(body);
  const emit=()=>{response.writeHead(status, { 'content-type': 'application/json; charset=utf-8', 'cache-control': 'no-store', 'x-content-type-options': 'nosniff', 'x-frame-options': 'DENY' });response.end(serialized);};
  const scope=configurationScope.getStore();
  if(scope)scope.responses.push(emit);else emit();
}

async function body(request) {
  let value = '';
  for await (const chunk of request) {
    value += chunk;
    if (value.length > 2_000_000) throw new Error('request body is too large');
  }
  return JSON.parse(value || '{}');
}

async function atomicWrite(path, value) {
  configurationScope.getStore()?.transaction.beginWrite();
  await mkdir(dirname(path), { recursive: true, mode: 0o700 });
  if (existsSync(path)) await copyFile(path, `${path}.backup`);
  await atomicText(path,value);
}

async function activity(level, event, details = {}) {
  configurationScope.getStore()?.transaction.beginWrite();
  await mkdir(dirname(activityFile), { recursive: true, mode: 0o700 });
  if (existsSync(activityFile) && (await stat(activityFile)).size > 1_000_000) await rename(activityFile, `${activityFile}.1`);
  await writeFile(activityFile, `${JSON.stringify({ timestamp: new Date().toISOString(), level, event, details })}\n`, { flag: 'a', mode: 0o600 });
}

async function history() {
  if (!existsSync(historyRoot)) return [];
  const entries = [];
  for (const name of (await readdir(historyRoot)).filter((item) => item.endsWith('.json')).sort().reverse()) {
    const document = JSON.parse(await readFile(join(historyRoot, name), 'utf8'));
    entries.push({ id: name.slice(0, -5), name: document.name, createdAt: document.createdAt, reason: document.reason });
  }
  return entries;
}

async function createSnapshot(config, reason = 'apply', name) {
  configurationScope.getStore()?.transaction.beginWrite();
  await mkdir(historyRoot, { recursive: true, mode: 0o700 });
  const id = `${Date.now()}-${randomBytes(4).toString('hex')}`;
  const document = { name: name || new Date().toLocaleString('en-AU'), createdAt: new Date().toISOString(), reason, config };
  await atomicWrite(join(historyRoot, `${id}.json`), `${JSON.stringify(document, null, 2)}\n`);
  return { id, ...document, config: undefined };
}

function configDiff(before, after, path = '$', changes = []) {
  if (JSON.stringify(before) === JSON.stringify(after)) return changes;
  if (!before || !after || typeof before !== 'object' || typeof after !== 'object' || Array.isArray(before) || Array.isArray(after)) {
    changes.push({ path, before, after }); return changes;
  }
  for (const key of new Set([...Object.keys(before), ...Object.keys(after)])) configDiff(before[key], after[key], `${path}.${key}`, changes);
  return changes;
}

async function queryDisplays() {
  try { const { stdout } = await execFileAsync('yabai', ['-m', 'query', '--displays'], { timeout: 10_000, maxBuffer: 1_000_000 }); return { displays: JSON.parse(stdout) }; }
  catch (error) { return { displays: [], unavailable: true, message: error.message }; }
}

async function detectHardware() {
  return detectMacHardware();
}

function assignSetupRoles(config, hardwareProfileId, setupId, displays, requested = {}) {
  const requirements = config.hardwareProfiles[hardwareProfileId].setups[setupId].match.displays;
  const used = new Set();
  const bindings = {};
  for (const requirement of requirements) {
    if (!requirement.role) continue;
    const requestedUuid = requested[requirement.role];
    const index = displays.findIndex((display, candidate) => !used.has(candidate)
      && (!requestedUuid || display.uuid === requestedUuid)
      && (!requirement.kind || display.kind === requirement.kind)
      && (!requirement.orientation || display.orientation === requirement.orientation));
    if (index < 0) throw new Error(`could not bind display role “${requirement.role}”`);
    used.add(index);
    bindings[requirement.role] = displays[index].uuid;
  }
  return bindings;
}

async function v3SetupState(config, machineOverride = null) {
  const [machine, hardware, displayResult] = await Promise.all([machineOverride || readMachine(), detectHardware(), queryDisplays()]);
  const snapshot = { unavailable: displayResult.unavailable === true, message: displayResult.message, displays: displayResult.displays || [] };
  const hardwareSelection = selectHardwareProfile(config, machine, hardware);
  const displays = describeDisplays(snapshot, machine);
  const key = topologyKey(displays);
  const setupCandidates = hardwareSelection.id ? matchingSetups(config, hardwareSelection.id, snapshot, machine) : [];
  const confirmedSetup = machine.topologySelections?.[key] || null;
  const setup = confirmedSetup && hardwareSelection.id ? config.hardwareProfiles[hardwareSelection.id]?.setups?.[confirmedSetup] : null;
  const bindingStatus = confirmedSetup && hardwareSelection.id
    ? setupBindingStatus(config, hardwareSelection.id, confirmedSetup, snapshot, machine)
    : { ready: false, missingRoles: [] };
  return {
    mutates: false,
    hardware,
    hardwareSelection,
    topologyKey: key,
    displays,
    unavailable: snapshot.unavailable,
    message: snapshot.message,
    setupCandidates,
    confirmedSetup,
    activeSetup: machine.activeSetup || null,
    compatibilityMode: setup?.compatibilityMode || null,
    workspaceConfigurations: setup?.workspaceConfigurations || {},
    bindingStatus,
    ready: Boolean(machine.hardwareProfileConfirmed && confirmedSetup && setupCandidates.includes(confirmedSetup) && bindingStatus.ready),
    machine,
    snapshot
  };
}

function compiledV3Document(config, resolution, source) {
  if(typeof source!=='string')throw new Error('v3 runtime compilation requires actual source bytes');
  return generationDocument(config, resolution, source);
}

async function querySnapshot() { return discoverState(await readMachine()); }

function targetFromPayload(payload) {
  if (payload.kind === 'profile') return { kind: 'profile', id: payload.target };
  if (payload.kind === 'mode') return { kind: 'mode', id: payload.target, mode: payload.target };
  return { kind: 'workspace', id: payload.target, mode: payload.mode };
}

async function livePlan(config, payload) {
  const validation = config.version === 3 ? validateV3(config) : validateV2(config);
  if (!validation.valid) return { validation };
  const machine=await readMachine();
  const snapshot=await discoverState(machine);
  let effectiveConfig = config;
  let resolution = null;
  let target = targetFromPayload(payload);
  if (config.version === 3) {
    const hardware = await detectHardware();
    resolution = resolveV3(config, { machine, hardware, snapshot });
    effectiveConfig = resolution.v2;
    if (target.kind === 'workspace' && !target.mode) {
      target = { ...target, mode: config.hardwareProfiles[resolution.hardwareProfileId].setups[resolution.setupId].compatibilityMode };
    }
  }
  const desired = buildDesiredState(effectiveConfig, compileV2(effectiveConfig), target, snapshot);
  const spaceLabelHints = await readSpaceLabelHints(stateRoot, desired, snapshot);
  const comparison = compareState(snapshot, desired, machine, { spaceLabelHints });
  const plan = buildExecutionPlan(snapshot, desired, comparison);
  return { validation, snapshot, desired, comparison, plan, resolution: resolution ? {
    hardwareProfileId: resolution.hardwareProfileId,
    setupId: resolution.setupId,
    topologyKey: resolution.topologyKey
  } : null, effectiveConfig };
}

function parseSkhdShortcutLine(line, source, config) {
  const match = line.match(/^\s*(.*?)\s*:\s*fish\s+-lc\s+(['"])(.*?)\2\s*$/);
  if (!match) return null;
  const chord = match[1].split(/\s+-\s+/); const key = chord.pop().trim();
  const modifiers = chord.join(' + ').split('+').map((item) => item.trim()).filter(Boolean).map((item) => ({ command: 'cmd', option: 'alt', control: 'ctrl' })[item] || item);
  if (modifiers.some((item) => !['cmd', 'ctrl', 'alt', 'shift', 'fn'].includes(item))) return null;
  const commands = match[3].split(';').map((item) => item.trim()).filter(Boolean);
  const direct = commands.find((command) => /^spacewright\s+(?:run|workspace)\s+[a-z][a-z0-9_]*\s+(?:solo|tall|wide)$/.test(command));
  const guardedModeCommand = commands.find((command) => /^spacewright\s+mode\s+(solo|tall|wide)$/.test(command));
  const modeCommand = commands.find((command) => /^work_(solo|tall|wide)$/.test(command));
  let action;
  if (direct) { const [, workspace, mode] = direct.match(/^spacewright\s+(?:run|workspace)\s+([a-z][a-z0-9_]*)\s+(solo|tall|wide)$/); action = { type: 'activateWorkspace', workspace, mode }; }
  else if (guardedModeCommand) action = { type: 'activateMode', mode: guardedModeCommand.split(/\s+/).at(-1) };
  else if (modeCommand) action = { type: 'activateMode', mode: modeCommand.slice(5) };
  else {
    const candidates = [];
    for (const [workspace, definition] of Object.entries(config.workspaces || {})) for (const [mode, variant] of Object.entries(definition.variants || {})) {
      if (variant.command) candidates.push({ command: variant.command, workspace, mode });
      candidates.push({ command: `${workspace}_${mode}`, workspace, mode });
    }
    const resolved = candidates.find((candidate) => commands.includes(candidate.command));
    if (resolved) action = { type: 'activateWorkspace', workspace: resolved.workspace, mode: resolved.mode };
    else {
      const legacy = commands.find((command) => /^[a-z][a-z0-9_]*_(solo|tall|wide)$/.test(command));
      if (!legacy) return null;
      action = { type: 'externalCommand', command: legacy };
    }
  }
  return {
    keys: { modifiers, key: key.toLowerCase() },
    action,
    source
  };
}

async function shortcutInventory(config) {
  const sources = [
    { path: join(configRoot, 'generated', 'spacewright.skhdrc'), label: 'SpaceWright generated fragment' },
    { path: skhdFile, label: 'skhd configuration' }
  ];
  const bindings = [];
  for (const source of sources) {
    if (!existsSync(source.path)) continue;
    const text = await readFile(source.path, 'utf8');
    for (const line of text.split('\n')) {
      const binding = parseSkhdShortcutLine(line, source.label, config);
      if (binding) bindings.push(binding);
    }
  }
  const unique = new Map();
  for (const binding of bindings) unique.set(`${binding.keys.modifiers.slice().sort().join('+')}+${binding.keys.key}:${JSON.stringify(binding.action)}`, binding);
  return { bindings: [...unique.values()], inspected: sources.filter((source) => existsSync(source.path)).map((source) => source.label), mutates: false };
}

async function commandCheck(command, args = ['--version']) {
  try { const { stdout, stderr } = await execFileAsync(command, args, { timeout: 2500, maxBuffer: 1_000_000 }); return { ok: true, detail: (stdout || stderr).trim().split('\n')[0] }; }
  catch (error) { return { ok: false, detail: error.message }; }
}

function taskView(task) {
  return { id: task.id, kind: task.kind, target: task.target, mode: task.mode, status: task.status, createdAt: task.createdAt, startedAt: task.startedAt, finishedAt: task.finishedAt, exitCode: task.exitCode, logs: task.logs.slice(-300) };
}

function appendTaskLog(task, line) {
  task.logs.push(line);
  if (task.logs.length > MAX_TASK_LOG_LINES) task.logs.splice(0, task.logs.length - MAX_TASK_LOG_LINES);
}

function rememberTask(task) {
  if(closing)return false;
  const removable = [...tasks.values()].filter((item) => !['queued', 'running'].includes(item.status)).sort((a, b) => a.createdAt.localeCompare(b.createdAt));
  while (tasks.size >= MAX_TASKS && removable.length) tasks.delete(removable.shift().id);
  if (tasks.size >= MAX_TASKS) return false;
  tasks.set(task.id, task);
  return true;
}

function commandsForExecution(config, payload) {
  if (payload.kind === 'mode') {
    if (!['solo', 'wide', 'tall'].includes(payload.target)) throw new Error('unknown mode');
    return { mode: payload.target, commands: [['apply', payload.target, '--json']] };
  }
  if (payload.kind === 'workspace') {
    if (!config.workspaces[payload.target] || !['solo', 'wide', 'tall'].includes(payload.mode)) throw new Error('unknown workspace or mode');
    if (!config.workspaces[payload.target].variants?.[payload.mode]) throw new Error('workspace has no variant for this mode');
    return { mode: payload.mode, commands: [['apply', payload.target, payload.mode, '--json']] };
  }
  if (payload.kind === 'profile') {
    const profile = config.profiles?.[payload.target]; if (!profile) throw new Error('unknown profile');
    return { mode: profile.mode, commands: [['apply', `--profile=${payload.target}`, '--json']] };
  }
  throw new Error('kind must be mode, workspace, or profile');
}

async function runTask(task, commands, beforeCommand) {
  return runWebTask(task, commands, { executable: join(packageRoot, 'bin', 'spacewright'),
    env: { ...process.env, SPACEWRIGHT_CONFIG_ROOT: configRoot, SPACEWRIGHT_STATE_ROOT: stateRoot }, activity, append: appendTaskLog, beforeCommand });
}

function enqueueTask(task, commands, beforeCommand) {
  taskQueue = taskQueue.catch(() => {}).then(() => runTask(task, commands, beforeCommand));
  return taskQueue;
}


async function executeRule(config, rule, {automated = true} = {}) {
  if(config.version!==2)throw new Error('rule execution is only supported by active v2 configurations');
  const checkCurrent=async()=>{
    const current=await readOperationalConfig();
    if(current.version!==2 || configRevision(current)!==configRevision(config)
      || automated && current.settings?.eventAutomationEnabled!==true)throw new Error('active configuration changed while rule execution was queued; evaluate again');
  };
  await checkCurrent();
  const kind = rule.then.activateProfile ? 'profile' : 'workspace'; const target = rule.then.activateProfile || rule.then.activateWorkspace;
  const execution = commandsForExecution(config, { kind, target, mode: rule.then.mode || 'solo' });
  // Carry the evaluated configuration into apply as well as checking the queue.
  // apply retains its own lease, deadline, generation and window preconditions.
  for(const command of execution.commands)command.push(`--expected-config-digest=${hash(config)}`);
  const id = randomBytes(10).toString('hex'); const task = { id, kind, target, mode: execution.mode, status: 'queued', createdAt: new Date().toISOString(), startedAt: null, finishedAt: null, exitCode: null, logs: [`SYSTEM matched rule ${rule.id}`], child: null };
  if (!rememberTask(task)) throw new Error('task capacity reached; wait for an active task to finish');
  void enqueueTask(task, execution.commands, checkCurrent); return task;
}

async function archiveConfig() {
  if (!existsSync(configFile)) return;
  configurationScope.getStore()?.transaction.beginWrite();
  const backupRoot = join(configRoot, 'backups');
  await mkdir(backupRoot, { recursive: true, mode: 0o700 });
  await copyFile(configFile, join(backupRoot, `config.v2.${Date.now()}.json`));
  const backups = (await readdir(backupRoot)).filter((name) => /^config\.v2\.[0-9]+\.json$/.test(name)).sort().reverse();
  await Promise.all(backups.slice(10).map((name) => unlink(join(backupRoot, name))));
}

function serializedConfig(config) {
  return `${JSON.stringify(config, null, 2)}\n`;
}

function configRevision(config) {
  return createHash('sha256').update(serializedConfig(config)).digest('hex');
}

async function currentConfigDocument() {
  const config = await readConfig();
  return { config, revision: configRevision(config) };
}

async function activeDocument() {
  const path = existsSync(configV3File) ? configV3File : configFile;
  const value = await stableRead(path, machineFile, {ownedWrite:Boolean(configurationScope.getStore())});
  const version = path === configV3File ? 3 : 2;
  if (value.config.version !== version) throw Object.assign(new Error('active configuration version does not match its file'), {statusCode:422});
  return {...value, path, version, backupPath:`${path}.backup`, revision:configRevision(value.config)};
}

// Setup writers retain the source bytes, machine and selected version across
// discovery and lock acquisition. No persistent action precedes this recheck.
async function setupDocument() {
  if(existsSync(configV3File) || existsSync(configFile))return activeDocument();
  return {...await stableRead(configFile,machineFile,{ownedWrite:Boolean(configurationScope.getStore()),allowMissingConfig:true}),path:configFile,version:0};
}

async function assertSetupDocument(document, machine = document.machine) {
  const current=await setupDocument();
  if(current.path!==document.path || current.version!==document.version || current.source!==document.source
    || JSON.stringify(current.machine)!==JSON.stringify(machine))throw new Error('configuration generation changed during setup activation');
}

async function verifySetupWrite(document, machine, runtime) {
  if(runtime) {
    const actual=JSON.parse(await readFile(runtimeFile,'utf8'));
    const verified=verifyRuntimeDocument(actual,runtime);
    if(!verified.ok)throw new Error(`setup runtime read-back verification failed: ${verified.detail}`);
  }
  await assertSetupDocument(document,machine);
}

async function backupDocument(active) {
  let source;
  try { source = await readFile(active.backupPath, 'utf8'); }
  catch(error) { if(error.code === 'ENOENT') throw Object.assign(new Error('no backup exists for the active configuration version'), {statusCode:404}); throw error; }
  let config;
  try { config = JSON.parse(source); } catch { throw Object.assign(new Error('the configuration backup is not valid JSON'), {statusCode:422}); }
  if(config?.version !== active.version) throw Object.assign(new Error('backup version differs from the active configuration'), {statusCode:422});
  return {source,config,backupRevision:hash(source)};
}

async function currentEditorDocument() {
  if (!existsSync(configV3File)) {
    const document = await currentConfigDocument();
    return { ...document, path: configFile, source: existsSync(configFile) ? 'v2' : 'starter', legacyAvailable: true };
  }
  const portableConfig = (await stableRead(configV3File, machineFile, {ownedWrite:Boolean(configurationScope.getStore())})).config;
  const revision = configRevision(portableConfig);
  const setupState = await v3SetupState(portableConfig);
  if (!setupState.ready) {
    return { config: structuredClone(unsavedStarterConfig), revision, path: configV3File, source: 'v3-unresolved', legacyAvailable: existsSync(configFile), setupRequired: true };
  }
  const resolution = resolveV3(portableConfig, { machine: setupState.machine, hardware: setupState.hardware, snapshot: setupState.snapshot });
  return {
    config: resolution.v2,
    revision,
    path: configV3File,
    source: 'v3-projection',
    legacyAvailable: existsSync(configFile),
    activeHardwareProfile: resolution.hardwareProfileId,
    activeSetup: resolution.setupId
  };
}

function compiledDocument(config) {
  return generationDocument(config, null, serializedConfig(config));
}

async function api(request, response, url) {
  if (request.headers['x-spacewright-token'] !== token) return json(response, 403, { error: 'invalid session token' });
  if (url.pathname === '/api/v3/config' && request.method === 'GET') {
    const config = existsSync(configV3File) ? (await stableRead(configV3File, machineFile, {ownedWrite:Boolean(configurationScope.getStore())})).config : existsSync(configFile) ? migrateV2ToV3(await readConfig()) : starterV3();
    return json(response, 200, { config, revision: configRevision(config), path: configV3File, source: existsSync(configV3File) ? 'v3' : existsSync(configFile) ? 'v2-migration-preview' : 'v3-starter' });
  }
  if (url.pathname === '/api/v3/validate' && request.method === 'POST') {
    const config = await body(request); const validation = validateV3(config);
    return json(response, validation.valid ? 200 : 422, { ...validation, mutates: false });
  }
  if (url.pathname === '/api/v3/setup' && request.method === 'GET') {
    const config = existsSync(configV3File) ? (await stableRead(configV3File, machineFile, {ownedWrite:Boolean(configurationScope.getStore())})).config : existsSync(configFile) ? migrateV2ToV3(await readConfig()) : starterV3();
    const validation = validateV3(config);
    if (!validation.valid) return json(response, 422, validation);
    return json(response, 200, await v3SetupState(config));
  }
  if (url.pathname === '/api/v3/setup/confirm' && request.method === 'POST') {
    const payload = await body(request);
    const document=await setupDocument();
    const config = payload.config || (document.version===3 ? document.config : document.version===2 ? migrateV2ToV3(document.config) : starterV3());
    const validation = validateV3(config); if (!validation.valid) return json(response, 422, validation);
    const hardwareProfileId = payload.hardwareProfile; const setupId = payload.setup;
    if (!config.hardwareProfiles?.[hardwareProfileId]?.setups?.[setupId]) return json(response, 422, { error: 'valid hardwareProfile and setup are required' });
    const currentMachine=normalizedMachine(document.machine);
    const [hardware, displayResult] = await Promise.all([detectHardware(), queryDisplays()]);
    if (displayResult.unavailable) return json(response, 503, { error: displayResult.message });
    const provisional = { ...currentMachine, displayBindings: { ...(currentMachine.displayBindings || {}), ...(payload.displayBindings || {}) }, displayKinds: { ...(currentMachine.displayKinds || {}), ...(payload.displayKinds || {}) } };
    const snapshot = { unavailable: false, displays: displayResult.displays };
    const displays = describeDisplays(snapshot, provisional);
    const candidates = matchingSetups(config, hardwareProfileId, snapshot, provisional);
    if (!candidates.includes(setupId)) return json(response, 422, { error: `setup “${setupId}” does not match the current displays`, candidates });
    let assigned;
    try { assigned = assignSetupRoles(config, hardwareProfileId, setupId, displays, payload.displayBindings || {}); }
    catch (error) { return json(response, 422, { error: error.message }); }
    const key = topologyKey(displays);
    const machine = {
      ...provisional,
      version: 2,
      hardwareProfile: hardwareProfileId,
      hardwareProfileConfirmed: true,
      detectedHardware: hardware,
      displayBindings: { ...(provisional.displayBindings || {}), ...assigned },
      topologySelections: { ...(provisional.topologySelections || {}), [key]: setupId },
      activeSetup: setupId
    };
    let runtime = null;
    await serializeConfigWrite(async () => {
      await assertSetupDocument(document);
      if(document.version===3 && serializedConfig(document.config)===serializedConfig(config))runtime=compiledV3Document(document.config,{machine,hardware,snapshot},document.source);
      await atomicWrite(machineFile, `${JSON.stringify(machine, null, 2)}\n`);
      if (runtime) {
        await atomicWrite(runtimeFile, `${JSON.stringify(runtime, null, 2)}\n`);
      }
      await verifySetupWrite(document,machine,runtime);
    });
    const setupState = await v3SetupState(config, machine);
    return json(response, 200, { confirmed: true, machine, topologyKey: key, hardwareProfile: hardwareProfileId, setup: setupId, setupState, runtimePath: runtime ? runtimeFile : null });
  }
  if (url.pathname === '/api/v3/setup/activate' && request.method === 'POST') {
    if (!existsSync(configV3File)) return json(response, 409, { error: 'save the v3 configuration before activation' });
    return serializeConfigWrite(async()=>{
      const document=await activeDocument();
      if(document.version!==3)return json(response,409,{error:'active configuration changed before activation'});
      const state=await v3SetupState(document.config,normalizedMachine(document.machine));
      if(!state.ready)return json(response,422,{error:'the current topology has not been confirmed',...state});
      const machine={...state.machine,activeSetup:state.confirmedSetup};
      const runtime=compiledV3Document(document.config,{machine,hardware:state.hardware,snapshot:state.snapshot},document.source);
      await assertSetupDocument(document);
      await atomicWrite(machineFile,`${JSON.stringify(machine,null,2)}\n`);
      await atomicWrite(runtimeFile,`${JSON.stringify(runtime,null,2)}\n`);
      await verifySetupWrite(document,machine,runtime);
      return json(response,200,{activated:true,setup:state.confirmedSetup,compatibilityMode:state.compatibilityMode,runtimePath:runtimeFile});
    });
  }
  if (url.pathname === '/api/v3/save' && request.method === 'POST') {
    const payload = await body(request); const config = payload.config || payload; const validation = validateV3(config);
    if (!validation.valid) return json(response, 422, validation);
    return await serializeConfigWrite(async () => {
      const current = existsSync(configV3File) ? (await stableRead(configV3File, machineFile, {ownedWrite:Boolean(configurationScope.getStore())})).config : existsSync(configFile) ? migrateV2ToV3(await readConfig()) : starterV3();
      const revision = configRevision(current);
      if (!payload.baseRevision) return json(response, 428, { error: 'baseRevision is required', code: 'revision_required', currentRevision: revision });
      if (payload.baseRevision !== revision) return json(response, 409, { error: 'configuration changed on disk', code: 'configuration_conflict', currentRevision: revision });
      const setupState = await v3SetupState(config);
      if (!setupState.ready) return json(response, 422, { error: 'confirm the detected hardware and display setup before saving v3', setup: setupState });
      const source = serializedConfig(config);
      const runtime = compiledV3Document(config, { machine: setupState.machine, hardware: setupState.hardware, snapshot: setupState.snapshot }, source);
      if (existsSync(configV3File)) {
        configurationScope.getStore().transaction.beginWrite();
        await copyFile(configV3File, `${configV3File}.backup`);
      }
      await atomicWrite(runtimeFile, `${JSON.stringify(runtime, null, 2)}\n`);
      await atomicWrite(configV3File, source);
      const readBack = (await stableRead(configV3File, machineFile, {ownedWrite:Boolean(configurationScope.getStore())})).config;
      if (serializedConfig(readBack) !== source) throw new Error('read-back verification failed');
      await activity('info', 'v3_configuration_saved', { hardwareProfile: setupState.hardwareSelection.id, setup: setupState.confirmedSetup });
      return json(response, 200, { saved: true, verified: true, revision: configRevision(readBack), path: configV3File, runtimePath: runtimeFile });
    });
  }
  if (url.pathname === '/api/config' && request.method === 'GET') {
    return json(response, 200, await currentEditorDocument());
  }
  if (url.pathname === '/api/config-backup' && request.method === 'GET') {
    const active = await activeDocument();
    const backup = await backupDocument(active);
    return json(response, 200, { config:backup.config, version:active.version, path:active.backupPath, baseRevision:active.revision, backupRevision:backup.backupRevision });
  }
  if (url.pathname === '/api/legacy-preview' && request.method === 'GET') return json(response, 200, { config: migrateV1(await readLegacyConfig()), source: 'legacy-preview', writes: false });
  if (url.pathname === '/api/machine' && request.method === 'GET') return json(response, 200, { machine: await readMachine(), path: machineFile });
  if (url.pathname === '/api/validate' && request.method === 'POST') {
    const config = await body(request);
    const validation = validateV2(config);
    return json(response, validation.valid ? 200 : 422, { ...validation, runtime: validation.valid ? compileV2(config) : null });
  }
  if (url.pathname === '/api/defaults' && request.method === 'GET') return json(response, 200, { config: starterConfig(), kind: 'spacewright' });
  if (url.pathname === '/api/diff' && request.method === 'POST') {
    const payload = await body(request); const candidate = payload.config || payload; const current = await currentConfigDocument();
    if (payload.baseRevision && payload.baseRevision !== current.revision) return json(response, 409, { error: 'configuration changed on disk; reload or compare before saving', code: 'configuration_conflict', currentRevision: current.revision });
    const changes = configDiff(current.config, candidate);
    return json(response, 200, { changes, count: changes.length, baseRevision: current.revision });
  }
  if (url.pathname === '/api/save' && request.method === 'POST') {
    const payload = await body(request); const config = payload.config || payload;
    return await serializeConfigWrite(async () => {
      if(existsSync(configV3File)) return json(response,409,{error:'v3 is active; edit and save in Hardware & Setups',code:'active_version_conflict'});
      const current = await currentConfigDocument();
      if (!payload.baseRevision) return json(response, 428, { error: 'baseRevision is required to prevent overwriting a newer configuration', code: 'revision_required', currentRevision: current.revision });
      if (payload.baseRevision !== current.revision) return json(response, 409, { error: 'configuration changed on disk; reload or compare before saving', code: 'configuration_conflict', currentRevision: current.revision });
      const validation = validateV2(config);
      if (!validation.valid) return json(response, 422, validation);
      const source = serializedConfig(config);
      await archiveConfig();
      await createSnapshot(current.config, 'before-apply');
      await atomicWrite(runtimeFile, `${JSON.stringify(compiledDocument(config), null, 2)}\n`);
      await atomicWrite(configFile, source);
      const readBack = await readConfig();
      if (serializedConfig(readBack) !== source) throw new Error('read-back verification failed');
      const snapshot = await createSnapshot(readBack, 'apply');
      await activity('info', 'configuration_saved', { snapshotId: snapshot.id });
      return json(response, 200, { saved: true, verified: true, revision: configRevision(readBack), snapshot, path: configFile, runtimePath: runtimeFile });
    });
  }
  if (url.pathname === '/api/history' && request.method === 'GET') return json(response, 200, { snapshots: await history() });
  if (url.pathname.startsWith('/api/history/') && request.method === 'GET') {
    const id = url.pathname.split('/').at(-1); const path = join(historyRoot, `${id}.json`);
    if (!/^[0-9]+-[a-f0-9]{8}$/.test(id) || !existsSync(path)) return json(response, 404, { error: 'snapshot not found' });
    const snapshot = JSON.parse(await readFile(path, 'utf8'));
    return json(response, 200, { snapshot: { id, ...snapshot }, changes: configDiff(await readConfig(), snapshot.config) });
  }
  if (url.pathname.match(/^\/api\/history\/[^/]+\/rename$/) && request.method === 'POST') {
    const id = url.pathname.split('/')[3]; const path = join(historyRoot, `${id}.json`); const payload = await body(request);
    if (!existsSync(path) || typeof payload.name !== 'string' || !payload.name.trim()) return json(response, 422, { error: 'valid snapshot name required' });
    const snapshot = JSON.parse(await readFile(path, 'utf8')); snapshot.name = payload.name.trim(); await atomicWrite(path, `${JSON.stringify(snapshot, null, 2)}\n`); return json(response, 200, { renamed: true });
  }
  if (url.pathname.match(/^\/api\/history\/[^/]+\/restore$/) && request.method === 'POST') {
    const id = url.pathname.split('/')[3];
    if (!/^[0-9]+-[a-f0-9]{8}$/.test(id)) return json(response, 404, {error:'snapshot not found'});
    const payload = await body(request);
    const result = await serializeConfigWrite(async () => {
      if (existsSync(configV3File)) return {status:409, body:{error:'v2 history restore is unavailable while v3 is active; use the active backup instead',code:'active_version_conflict'}};
      const active = await activeDocument();
      if (!payload.baseRevision) return {status:428, body:{error:'baseRevision is required to prevent overwriting a newer configuration',code:'revision_required',currentRevision:active.revision}};
      if (payload.baseRevision !== active.revision) return {status:409, body:{error:'configuration changed on disk; reload or compare before restoring',code:'configuration_conflict',currentRevision:active.revision}};
      let snapshot;
      try { snapshot = JSON.parse(await readFile(join(historyRoot, `${id}.json`), 'utf8')); }
      catch (error) {
        if (error.code === 'ENOENT') return {status:404, body:{error:'snapshot not found'}};
        if (error instanceof SyntaxError) return {status:422, body:{error:'snapshot is not valid JSON'}};
        throw error;
      }
      const validation = validateV2(snapshot?.config);
      if (!validation.valid) return {status:422, body:validation};
      const source = serializedConfig(snapshot.config);
      const runtime = generationDocument(snapshot.config, null, source);
      const recovery = await createSnapshot(active.config, 'before-restore');
      await atomicWrite(configFile, source);
      await atomicWrite(runtimeFile, serializedConfig(runtime));
      const readBack = await activeDocument();
      const savedRuntime = JSON.parse(await readFile(runtimeFile, 'utf8'));
      if (readBack.path !== active.path || readBack.version !== 2 || readBack.source !== source
        || JSON.stringify(readBack.machine) !== JSON.stringify(active.machine)
        || hash(savedRuntime) !== hash(generationDocument(readBack.config, null, readBack.source))) throw new Error('history restore read-back verification failed; saved generation is incomplete');
      return {status:200, body:{restored:true,verified:true,config:readBack.config,revision:readBack.revision,recoverySnapshot:recovery}};
    });
    if (result.status === 200) {
      try { await activity('info', 'snapshot_restored', {id}); }
      catch (error) { result.body.warnings = [`Configuration restored, but the activity log could not be written: ${error.message}`]; }
    }
    return json(response, result.status, result.body);
  }
  if (url.pathname.startsWith('/api/history/') && request.method === 'DELETE') {
    const id = url.pathname.split('/').at(-1); const path = join(historyRoot, `${id}.json`); if (!existsSync(path)) return json(response, 404, { error: 'snapshot not found' }); await unlink(path); return json(response, 200, { deleted: true });
  }
  if (url.pathname === '/api/preview' && request.method === 'POST') {
    const payload = await body(request); const config = payload.config || await readOperationalConfig();
    const normalizedPayload = payload.profile ? { kind: 'profile', target: payload.profile } : payload.kind && payload.target ? payload : { kind: 'mode', target: payload.mode || 'solo' };
    let result; try { result = await livePlan(config, normalizedPayload); } catch (error) { return json(response, 422, { error: error.message }); }
    if (!result.validation.valid) return json(response, 422, result.validation);
    return json(response, 200, { dryRun: true, mutates: false, ...result });
  }
  if (url.pathname === '/api/state' && request.method === 'GET') return json(response, 200, { snapshot: await querySnapshot(), mutates: false });
  if (url.pathname === '/api/capture' && request.method === 'POST') {
    const payload = await body(request); const machine = await readMachine(); const snapshot = await discoverState(machine);
    if (snapshot.completeness !== 'complete') return json(response, 503, { error: snapshot.message });
    try {
      const capture=captureWorkspace(snapshot,payload), captureId=randomBytes(16).toString('hex');
      for(const [id,value] of captures)if(Date.now()-value.createdAt>300000)captures.delete(id);
      while(captures.size>=20)captures.delete(captures.keys().next().value);
      captures.set(captureId,{capture,snapshot,machine,createdAt:Date.now()});
      return json(response,200,{...capture,captureId,mutates:false});
    } catch(error) { return json(response,422,{error:error.message,code:error.code,details:error.details}); }
  }
  if(url.pathname === '/api/capture/merge' && request.method === 'POST') {
    const payload=await body(request);
    if(existsSync(configV3File)) return json(response,409,{error:'Capture merge is unavailable in the v3 projection editor; use CLI portable capture or edit Hardware & Setups.',code:'capture_version_unsupported'});
    const saved=captures.get(payload.captureId);
    if(!saved || Date.now()-saved.createdAt>300000) return json(response,409,{error:'Capture preview expired; capture the Space again.',code:'capture_expired'});
    try { return json(response,200,{...mergeCapturedWorkspace(payload.config,saved.capture,saved.snapshot,saved.machine),mutates:false}); }
    catch(error) { return json(response,422,{error:error.message,code:error.code}); }
  }
  if (url.pathname === '/api/tasks' && request.method === 'GET') return json(response, 200, { tasks: [...tasks.values()].sort((a, b) => b.createdAt.localeCompare(a.createdAt)).slice(0, 50).map(taskView) });
  if (url.pathname === '/api/transition-history' && request.method === 'GET') {
    const limit = Number(url.searchParams.get('limit') || 50);
    return json(response, 200, { transitions: await readTransitionHistory(stateRoot, limit), retention: 100 });
  }
  if (url.pathname === '/api/transition-history' && request.method === 'DELETE') {
    await clearTransitionHistory(stateRoot);
    await activity('info', 'transition_history_cleared');
    return json(response, 200, { cleared: true });
  }
  if (url.pathname === '/api/rules/evaluate' && request.method === 'POST') {
    const payload = await body(request); const active=await readOperationalConfig();
    if(active.version!==2)return json(response,409,{error:'rules are supported only by the active v2 configuration',code:'rules_version_unsupported',version:active.version});
    const config = payload.config || active; const validation = validateV2(config);
    if (!validation.valid) return json(response, 422, validation);
    const snapshot = await querySnapshot();
    const topology = snapshot.unavailable ? 'unknown' : classifyTopology(snapshot.displays.map((display) => ({ ...display, 'is-built-in': display.builtIn, 'is-visible': display.visible })));
    const context = ruleContext(config, payload.event || 'manual', snapshot, topology); const rules = matchingRules(config, context);
    if (!payload.execute) return json(response, 200, { context, matches: rules, mutates: false });
    if (snapshot.completeness !== 'complete') return json(response, 503, { error: snapshot.message });
    if (payload.confirmed !== true) return json(response, 422, { error: 'explicit execution confirmation is required' });
    if(configRevision(config)!==configRevision(active))return json(response,409,{error:'save the rule configuration before executing',code:'configuration_conflict'});
    const launched = []; for (const rule of rules) launched.push(taskView(await executeRule(config, rule, {automated:false})));
    return json(response, 202, { context, tasks: launched });
  }
  if (url.pathname === '/api/execute' && request.method === 'POST') {
    const payload = await body(request); if (payload.confirmed !== true) return json(response, 422, { error: 'explicit execution confirmation is required' });
    const config = await readOperationalConfig(); const validation = config.version === 3 ? validateV3(config) : validateV2(config); if (!validation.valid) return json(response, 422, validation);
    if (!payload.expectedPlanId || !payload.expectedConfigDigest || !payload.expectedSnapshotId) return json(response, 428, { error: 'preview the target immediately before running it', code: 'preview_required' });
    let currentPlan;
    try { currentPlan = await livePlan(config, payload); } catch (error) { return json(response, 422, { error: error.message }); }
    if (!currentPlan.validation.valid) return json(response, 422, currentPlan.validation);
    if (currentPlan.plan.planId !== payload.expectedPlanId || currentPlan.plan.configDigest !== payload.expectedConfigDigest || false /* full snapshot is diagnostic; stable plan carries relevant preconditions */) {
      return json(response, 409, { error: 'the configuration or desktop changed after preview; review the refreshed plan before running', code: 'plan_stale', plan: currentPlan.plan, comparison: currentPlan.comparison });
    }
    const executionPayload = config.version === 3 && payload.kind === 'workspace' && !payload.mode
      ? { ...payload, mode: currentPlan.plan.target.mode }
      : payload;
    let execution; try { execution = commandsForExecution(currentPlan.effectiveConfig || config, executionPayload); } catch (error) { return json(response, 422, { error: error.message }); }
    for (const command of execution.commands) command.push(`--expected-plan-id=${payload.expectedPlanId}`, `--expected-config-digest=${payload.expectedConfigDigest}`, `--expected-snapshot-id=${payload.expectedSnapshotId}`);
    const id = randomBytes(10).toString('hex'); const task = { id, kind: payload.kind, target: payload.target, mode: execution.mode, status: 'queued', createdAt: new Date().toISOString(), startedAt: null, finishedAt: null, exitCode: null, logs: [], child: null };
    if (!rememberTask(task)) return json(response, 429, { error: 'task capacity reached; wait for an active task to finish', code: 'task_capacity' });
    void enqueueTask(task, execution.commands); return json(response, 202, { task: taskView(task) });
  }
  if (url.pathname.match(/^\/api\/tasks\/[a-f0-9]+$/) && request.method === 'GET') { const id = url.pathname.split('/').at(-1); const task = tasks.get(id); return task ? json(response, 200, { task: taskView(task) }) : json(response, 404, { error: 'task not found' }); }
  if (url.pathname.match(/^\/api\/tasks\/[a-f0-9]+\/cancel$/) && request.method === 'POST') { const id = url.pathname.split('/')[3]; const task = tasks.get(id); if (!task) return json(response, 404, { error: 'task not found' }); if (!['queued', 'running'].includes(task.status)) return json(response, 409, { error: 'task is no longer running' }); cancelWebTask(task); appendTaskLog(task, 'SYSTEM cancellation requested'); return json(response, 200, { task: taskView(task) }); }
  if (url.pathname === '/api/topology' && request.method === 'GET') { const result = await queryDisplays(); return json(response, 200, { ...result, topology: classifyTopology(result.displays), mutates: false }); }
  if (url.pathname === '/api/diagnostics' && request.method === 'GET') {
    const selectedPath = existsSync(configV3File) ? configV3File : configFile;
    let document = null, loadingError = null;
    try { document = await stableRead(selectedPath, machineFile); }
    catch (error) {
      if (!(error instanceof SyntaxError) && !['ENOENT','EACCES','EISDIR'].includes(error.code) && !/configuration.*(generation|save)/.test(error.message)) throw error;
      loadingError = `configuration cannot be loaded or verified: ${error.message}`;
    }
    const portableConfig = document?.config;
    const validVersion = portableConfig?.version === (selectedPath === configV3File ? 3 : 2);
    const validation = loadingError ? {valid:false,errors:[loadingError]}
      : !validVersion ? {valid:false,errors:['active configuration version does not match its filename']}
      : portableConfig?.version === 3 ? validateV3(portableConfig) : validateV2(portableConfig);
    const machine = document?.machine || {};
    const snapshot = await discoverState(machine);
    const yabai = await commandCheck('yabai');
    let config = portableConfig?.version === 3 ? null : portableConfig;
    let v3Resolution = null;
    let resolutionError = !validation.valid ? 'configuration is invalid; hardware setup cannot be verified'
      : snapshot.completeness !== 'complete' ? snapshot.message || 'display discovery is incomplete' : null;
    if (portableConfig?.version === 3 && !resolutionError) {
      try {
        const hardware = await detectHardware();
        v3Resolution = {...resolveV3(portableConfig, {machine,hardware,snapshot}),machine,hardware,snapshot};
        config = v3Resolution.v2;
      } catch (error) { resolutionError = error.message; }
    }
    const topology = snapshot.unavailable ? 'unknown' : classifyTopology(snapshot.displays.map((display) => ({ ...display, 'is-built-in': display.builtIn, 'is-visible': display.visible })));
    const duplicateLabels = [...new Set(snapshot.spaces.map((space) => space.label).filter(Boolean).filter((label, index, labels) => labels.indexOf(label) !== index))];
    const missingBindings = Object.entries(machine.displayBindings || {}).filter(([, uuid]) => !snapshot.displays.some((display) => display.uuid === uuid)).map(([role]) => role);
    const expectedRuntime = validation.valid && !resolutionError
      ? generationDocument(portableConfig, v3Resolution, document.source) : null;
    let runtimeSource = null, runtimeCheck;
    try {
      runtimeSource = await readFile(runtimeFile, 'utf8');
      const runtime = JSON.parse(runtimeSource);
      runtimeCheck = expectedRuntime ? verifyRuntimeDocument(runtime, expectedRuntime) : null;
    } catch (error) {
      if (!(error instanceof SyntaxError) && !['ENOENT','EACCES','EISDIR'].includes(error.code)) throw error;
      runtimeCheck = {ok:false,detail:`compiled runtime is ${error.code === 'ENOENT' ? 'missing' : 'unreadable'}: ${error.message}; run spacewright config-compile`};
    }
    if (!expectedRuntime) runtimeCheck = {ok:null,detail:`compiled runtime cannot be verified: ${loadingError || resolutionError || 'configuration is invalid'}${runtimeCheck?.ok === false ? `; ${runtimeCheck.detail}` : ''}`};
    const packageVersion = (await readFile(join(packageRoot, 'VERSION'), 'utf8')).trim();
    const packagedRelease = basename(resolve(packageRoot, '..')) === 'releases';
    const inferredMode = v3Resolution
      ? portableConfig.hardwareProfiles[v3Resolution.hardwareProfileId].setups[v3Resolution.setupId].compatibilityMode
      : topology === 'solo' ? 'solo' : topology.startsWith('tall') ? 'tall' : topology.startsWith('wide') ? 'wide' : null;
    let reconciliation = null;
    if (validation.valid && !snapshot.unavailable && inferredMode && config?.modes?.[inferredMode] && snapshot.completeness === 'complete') {
      const desired = buildDesiredState(config, compileV2(config), { kind: 'mode', id: inferredMode, mode: inferredMode }, snapshot);
      const spaceLabelHints = await readSpaceLabelHints(stateRoot, desired, snapshot);
      reconciliation = compareState(snapshot, desired, machine, { spaceLabelHints });
    }
    const runsRoot = join(stateRoot, 'runs');
    const runFiles = existsSync(runsRoot) ? (await readdir(runsRoot)).filter((name) => /^[0-9]+-[a-f0-9]{8}\.json$/.test(name)).sort().reverse().slice(0, 10) : [];
    const recentRuns = [];
    for (const name of runFiles) {
      try {
        const run = JSON.parse(await readFile(join(runsRoot, name), 'utf8'));
        recentRuns.push({ runId: run.runId, status: run.status, target: run.target, createdAt: run.createdAt, finishedAt: run.finishedAt || null, exitCode: run.exitCode ?? null, planId: run.plan?.planId || null });
      } catch {}
    }
    const recentTransitions = await readTransitionHistory(stateRoot, 10);
    let generationError = loadingError;
    if (document) {
      try {
        const currentPath = existsSync(configV3File) ? configV3File : configFile;
        const current = await stableRead(selectedPath, machineFile);
        if (currentPath !== selectedPath || current.source !== document.source
          || JSON.stringify(current.machine) !== JSON.stringify(machine)) throw new Error('configuration or machine generation changed during diagnostics');
        let currentRuntime = null;
        try { currentRuntime = await readFile(runtimeFile, 'utf8'); }
        catch (error) { if (!['ENOENT','EACCES','EISDIR'].includes(error.code)) throw error; }
        if (currentRuntime !== runtimeSource) throw new Error('runtime generation changed during diagnostics');
      } catch (error) { generationError = `generation cannot be verified: ${error.message}`; }
    }
    if (generationError) {runtimeCheck = {ok:null,detail:generationError};reconciliation = null;}
    const checks = [
      { id: 'yabai', ok: yabai.ok, detail: yabai.detail },
      { id: 'accessibility_query', ok: snapshot.completeness === 'complete', detail: snapshot.completeness !== 'complete' ? snapshot.message : `${snapshot.windows.length} windows queried` },
      { id: 'scripting_addition', ok: null, detail: 'not proven by read-only queries; live mutation remains unverified' },
      { id: 'display', ok: snapshot.displays.length > 0, detail: `${snapshot.displays.length} detected; topology ${topology}` },
      { id: 'display_bindings', ok: generationError || snapshot.completeness !== 'complete' ? null : missingBindings.length === 0, detail: generationError || (snapshot.completeness !== 'complete' ? snapshot.message : null) || (missingBindings.length ? `disconnected or stale: ${missingBindings.join(', ')}` : 'all bound roles are connected') },
      { id: 'space_labels', ok: snapshot.completeness !== 'complete' ? null : duplicateLabels.length === 0, detail: snapshot.completeness !== 'complete' ? snapshot.message : duplicateLabels.length ? `duplicates: ${duplicateLabels.join(', ')}` : `${snapshot.spaces.filter((space) => space.label).length} unique labels` },
      { id: 'backend', ok: true, detail: 'loopback authenticated writes' },
      { id: 'schema', ok: generationError ? null : validation.valid, detail: generationError || (validation.valid ? 'valid' : validation.errors.join('; ')) },
      ...(portableConfig?.version === 3 ? [{ id: 'hardware_setup', ok: generationError || !validation.valid || snapshot.completeness !== 'complete' ? null : Boolean(v3Resolution), detail: generationError || resolutionError || `${v3Resolution.hardwareProfileId} · ${v3Resolution.setupId}` }] : []),
      { id: 'compiled_runtime', ...runtimeCheck },
      { id: 'workspace', ok: generationError || !validation.valid || !config ? null : Object.keys(config.workspaces || {}).length > 0, detail: generationError || (!validation.valid || !config ? `workspace configuration cannot be verified: ${resolutionError}` : `${Object.keys(config.workspaces || {}).length} configured`) },
      { id: 'build_identity', ok: packagedRelease ? basename(packageRoot) === packageVersion : true, detail: packagedRelease ? `directory ${basename(packageRoot)}; VERSION ${packageVersion}` : `development checkout; VERSION ${packageVersion}` }
    ];
    if (reconciliation) checks.push({ id: 'current_mode_state', ok: reconciliation.converged, detail: `${inferredMode}: ${reconciliation.counts.blocker} blockers, ${reconciliation.counts.change} changes, ${reconciliation.counts.warning} warnings` });
    checks.push({ id: 'execution_history', ok: recentRuns.length ? !['failed', 'stale', 'partial'].includes(recentRuns[0].status) : null, detail: recentRuns.length ? `${recentRuns.length} recent; latest ${recentRuns[0].status}` : 'no recorded apply runs' });
    checks.push({ id: 'transition_history', ok: recentTransitions.length ? !['failed', 'timed_out'].includes(recentTransitions[0].status) : null, detail: recentTransitions.length ? `${recentTransitions.length} recent; latest ${recentTransitions[0].status}` : 'no recorded shortcut or CLI transitions' });
    return json(response, 200, { generatedAt: new Date().toISOString(), topology, snapshotId: snapshot.snapshotId, inferredMode, reconciliation, recentRuns, recentTransitions, checks });
  }
  if (url.pathname === '/api/self-test' && request.method === 'POST') {
    const config = await readOperationalConfig(); const validation = config.version === 3 ? validateV3(config) : validateV2(config);
    let compiled = null; let resolutionError = null;
    if (validation.valid) {
      try {
        if (config.version === 3) { const state = await v3SetupState(config); compiled = compileV3(config, { machine: state.machine, hardware: state.hardware, snapshot: state.snapshot }); }
        else compiled = compileV2(config);
      } catch (error) { resolutionError = error.message; }
    }
    const valid = validation.valid && !resolutionError;
    await activity(valid ? 'info' : 'error', 'self_test', { valid, resolutionError });
    return json(response, valid ? 200 : 422, { valid, errors: [...validation.errors, ...(resolutionError ? [resolutionError] : [])], compiled: Boolean(compiled), mutates: false });
  }
  if (url.pathname === '/api/activity' && request.method === 'GET') { const lines = existsSync(activityFile) ? (await readFile(activityFile, 'utf8')).trim().split('\n').filter(Boolean).slice(-200).reverse().map(JSON.parse) : []; return json(response, 200, { entries: lines }); }
  if (url.pathname === '/api/import' && request.method === 'POST') {
    const payload = await body(request);
    let config;
    try { config = YAML.parse(payload.text); }
    catch (error) { return json(response, 422, { valid: false, error: `YAML parse failed: ${error.message}` }); }
    const validation = config?.version === 3 ? validateV3(config) : config?.version === 2 ? validateV2(config)
      : { valid: false, errors: ['unsupported portable configuration version; expected 2 or 3'], warnings: [] };
    return json(response, validation.valid ? 200 : 422, { ...validation, config, mutates: false });
  }
  if (url.pathname === '/api/export' && request.method === 'GET') {
    const config = await readOperationalConfig();
    const validation = config?.version === 3 ? validateV3(config) : config?.version === 2 ? validateV2(config)
      : { valid: false, errors: ['unsupported portable configuration version'] };
    if (!validation.valid) return json(response, 422, { error: 'active portable configuration is invalid', ...validation });
    response.writeHead(200, { 'content-type': 'application/yaml; charset=utf-8', 'content-disposition': 'attachment; filename="spacewright.yaml"', 'cache-control': 'no-store' });
    return response.end(YAML.stringify(config));
  }
  if (url.pathname === '/api/restore-backup' && request.method === 'POST') {
    const payload = await body(request);
    if (!payload.version || !payload.baseRevision || !payload.backupRevision) return json(response, 428, {error:'version, baseRevision and backupRevision are required',code:'revision_required'});
    return serializeConfigWrite(async () => {
      const active = await activeDocument();
      if(payload.version !== active.version || payload.baseRevision !== active.revision) return json(response,409,{error:'active configuration changed; reload the backup preview',code:'configuration_conflict'});
      const backup = await backupDocument(active);
      if(payload.backupRevision !== backup.backupRevision) return json(response,409,{error:'backup changed; preview it again before restoring',code:'backup_conflict'});
      const validation = active.version === 3 ? validateV3(backup.config) : validateV2(backup.config);
      if(!validation.valid) return json(response,422,{error:'the configuration backup is invalid',...validation});
      let resolution = null;
      if(active.version === 3) {
        const setup = await v3SetupState(backup.config);
        if(!setup.ready) return json(response,422,{error:'backup requires confirmed hardware, topology and display bindings'});
        resolution = {machine:setup.machine,hardware:setup.hardware,snapshot:setup.snapshot};
      }
      // Compilation must finish before even the first backup rotation. Keep the
      // source bytes in memory because atomicWrite replaces the .backup file.
      const runtime = generationDocument(backup.config,resolution,backup.source);
      await atomicWrite(active.path,backup.source);
      await atomicWrite(runtimeFile,serializedConfig(runtime));
      const readBack = await activeDocument();
      const savedRuntime = JSON.parse(await readFile(runtimeFile,'utf8'));
      const expected = generationDocument(readBack.config,resolution,readBack.source);
      if(readBack.path !== active.path || readBack.version !== active.version || readBack.source !== backup.source
        || JSON.stringify(readBack.machine) !== JSON.stringify(active.machine)
        || hash(savedRuntime) !== hash(expected)) throw new Error('backup restore read-back verification failed; saved generation is incomplete');
      return json(response,200,{restored:true,verified:true,config:readBack.config,version:active.version,revision:readBack.revision,path:active.path,runtimePath:runtimeFile});
    });
  }
  if (url.pathname === '/api/skhd' && request.method === 'POST') {
    const config = await body(request);
    const validation = validateV2(config);
    if (!validation.valid) return json(response, 422, validation);
    const path = join(configRoot, 'generated', 'spacewright.skhdrc');
    await atomicWrite(path, compileSkhd(config));
    return json(response, 200, { saved: true, path });
  }
  if (url.pathname === '/api/display-bindings' && request.method === 'POST') {
    const payload = await body(request);
    return serializeConfigWrite(async () => {
      const document=await setupDocument();
      const config = payload.config || (document.version ? document.config : await readOperationalConfig());
      if (payload.config) {
        const validation = config.version === 3 ? validateV3(config) : validateV2(config);
        if (!validation.valid) return json(response, 422, { error: 'candidate configuration is invalid', ...validation });
      }
      if (!payload.displayBindings || typeof payload.displayBindings !== 'object' || Array.isArray(payload.displayBindings)) return json(response, 422, { error: 'displayBindings must be an object' });
      for (const [role, uuid] of Object.entries(payload.displayBindings)) {
        if (!config.displayRoles[role]) return json(response, 422, { error: `unknown display role: ${role}` });
        if (typeof uuid !== 'string' || !/^[A-Za-z0-9-]{8,}$/.test(uuid)) return json(response, 422, { error: `invalid display UUID for ${role}` });
      }
      const uuids = Object.values(payload.displayBindings);
      if (new Set(uuids).size !== uuids.length) return json(response, 422, { error: 'one display UUID cannot be bound to multiple roles' });
      const machine = {...normalizedMachine(document.machine),displayBindings:payload.displayBindings};
      let runtime;
      if(document.version===3) {
        const portable=document.config;
        const setup=await v3SetupState(portable,machine);
        if(!setup.ready)throw Object.assign(new Error('display bindings require confirmed topology before activation'),{statusCode:422});
        runtime=compiledV3Document(portable,{machine,hardware:setup.hardware,snapshot:setup.snapshot},document.source);
      } else if(document.version===2)runtime=generationDocument(document.config,null,document.source);
      await assertSetupDocument(document);
      await atomicWrite(machineFile,`${JSON.stringify(machine,null,2)}\n`);
      if(runtime)await atomicWrite(runtimeFile,`${JSON.stringify(runtime,null,2)}\n`);
      await verifySetupWrite(document,machine,runtime);
      return json(response, 200, { saved: true, machine, path: machineFile });
    });
  }
  if (url.pathname === '/api/displays' && request.method === 'GET') {
    return json(response, 200, { ...(await queryDisplays()), mutates: false });
  }
  if (url.pathname === '/api/apps' && request.method === 'GET') {
    try {
      const { stdout } = await execFileAsync('yabai', ['-m', 'query', '--windows'], { timeout: 2500, maxBuffer: 4_000_000 });
      const apps = [...new Set(JSON.parse(stdout).map((window) => window.app).filter(Boolean))].sort();
      return json(response, 200, { apps, mutates: false });
    } catch (error) {
      return json(response, 200, { apps: [], unavailable: true, message: error.message, mutates: false });
    }
  }
  if (url.pathname === '/api/shortcuts' && request.method === 'GET') return json(response, 200, await shortcutInventory(await readConfig()));
  return json(response, 404, { error: 'not found' });
}

const mime = { '.html': 'text/html; charset=utf-8', '.js': 'text/javascript; charset=utf-8', '.css': 'text/css; charset=utf-8', '.svg': 'image/svg+xml' };
function trustedLoopbackRequest(request) {
  const address = server.address();
  const port = typeof address === 'object' && address ? address.port : null;
  const host = String(request.headers.host || '').toLowerCase();
  const trustedHosts = new Set([`127.0.0.1:${port}`, `localhost:${port}`, `[::1]:${port}`]);
  if (!trustedHosts.has(host)) return false;
  const origin = request.headers.origin;
  return !origin || origin === `http://${host}`;
}
const server = http.createServer(async (request, response) => {
  try {
    if(closing)return json(response,503,{error:'configurator is stopping'});
    if (!trustedLoopbackRequest(request)) return json(response, 403, { error: 'untrusted local request origin' });
    const url = new URL(request.url, 'http://127.0.0.1');
    if (url.pathname.startsWith('/api/')) return await api(request, response, url);
    const relative = url.pathname === '/' ? 'index.html' : url.pathname.slice(1);
    if (relative.includes('..')) return json(response, 400, { error: 'invalid path' });
    const content = await readFile(join(publicRoot, relative));
    response.writeHead(200, {
      'content-type': mime[extname(relative)] || 'application/octet-stream',
      'cache-control': 'no-store',
      'content-security-policy': "default-src 'self'; script-src 'self'; style-src 'self' 'unsafe-inline'; connect-src 'self'; img-src 'self' data:; frame-ancestors 'none'",
      'referrer-policy': 'no-referrer',
      'x-content-type-options': 'nosniff',
      'x-frame-options': 'DENY'
    });
    response.end(content);
  } catch (error) {
    if (error.code === 'ENOENT') return json(response, 404, { error: 'not found' });
    json(response, error.statusCode || 500, { error: error.message });
  }
});

server.listen(listenPort, '127.0.0.1', async () => {
  const { port } = server.address();
  const url = `http://127.0.0.1:${port}/?token=${token}${initialView ? `&view=${initialView}` : ''}`;
  await atomicWrite(sessionFile, `${JSON.stringify({ formatVersion: 1, pid: process.pid, port, startedAt: new Date().toISOString() }, null, 2)}\n`);
  process.stdout.write(`SPACEWRIGHT_CONFIGURATOR_URL=${url}\n`);
  if (!process.argv.includes('--no-open')) execFile('open', [url], () => {});
});

const monitor = createAutomationMonitor({readConfig:readOperationalConfig,querySnapshot,activity,executeRule,
  activateSetup: async (topology, stopped) => {
    if(!existsSync(configV3File))return false;
    await serializeConfigWrite(async () => {
      if(stopped())return;
      const document=await activeDocument();
      if(document.version!==3)return;
      const setupState=await v3SetupState(document.config,normalizedMachine(document.machine));
      if(stopped())return;
      if(!setupState.ready) {
        await activity('info','v3_topology_confirmation_required',{topologyKey:setupState.topologyKey,candidates:setupState.setupCandidates});return;
      }
      const machine={...setupState.machine,activeSetup:setupState.confirmedSetup};
      const runtime=compiledV3Document(document.config,{machine,hardware:setupState.hardware,snapshot:setupState.snapshot},document.source);
      await assertSetupDocument(document);
      await atomicWrite(machineFile,`${JSON.stringify(machine,null,2)}\n`);
      await atomicWrite(runtimeFile,`${JSON.stringify(runtime,null,2)}\n`);
      await verifySetupWrite(document,machine,runtime);
      await activity('info','v3_setup_activated',{hardwareProfile:setupState.hardwareSelection.id,setup:setupState.confirmedSetup,topologyKey:setupState.topologyKey});
    });
    return true;
  }
});
monitor.start();
process.on('SIGUSR1', () => { void monitor.trigger('wake').catch(error => {process.stderr.write(`wake event failed: ${error.message}\n`);}); });
for (const signal of ['SIGINT','SIGTERM'])process.on(signal,async()=>{
  if(closing)return;closing=true;
  const monitorStopped=monitor.stop();
  for(const task of tasks.values())if(['queued','running'].includes(task.status))cancelWebTask(task);
  await monitorStopped;
  await taskQueue.catch(()=>{});
  await configWriteQueue.catch(()=>{});
  server.close(async()=>{
    try{const session=JSON.parse(await readFile(sessionFile,'utf8'));if(session.pid===process.pid)await unlink(sessionFile);}catch{}
    process.exit(0);
  });
});
