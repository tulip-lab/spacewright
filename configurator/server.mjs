#!/usr/bin/env node

import http from 'node:http';
import { readFile, writeFile, rename, mkdir, copyFile, readdir, unlink } from 'node:fs/promises';
import { existsSync } from 'node:fs';
import { dirname, extname, join, resolve } from 'node:path';
import { randomBytes } from 'node:crypto';
import { createHash } from 'node:crypto';
import { execFile, spawn } from 'node:child_process';
import { promisify } from 'node:util';
import YAML from 'yaml';
import { CONFIG_COMPILER_VERSION, compileSkhd, compileV2, migrateV1, starterConfig, validateV2 } from './lib/config-v2.mjs';

const execFileAsync = promisify(execFile);
const args = Object.fromEntries(process.argv.slice(2).map((arg) => arg.split('=', 2)));
const packageRoot = resolve(args['--package-root'] || join(import.meta.dirname, '..'));
const configRoot = resolve(args['--config-root'] || join(process.env.HOME, '.config', 'spacewright'));
const stateRoot = resolve(args['--state-root'] || join(process.env.HOME, '.local', 'state', 'spacewright'));
const configFile = join(configRoot, 'config.v2.json');
const skhdFile = resolve(args['--skhd-file'] || join(process.env.HOME, '.config', 'skhd', 'skhdrc'));
const machineFile = join(stateRoot, 'machine.json');
const runtimeFile = join(configRoot, 'generated', 'runtime.json');
const historyRoot = join(stateRoot, 'history');
const activityFile = join(stateRoot, 'activity.jsonl');
const publicRoot = join(packageRoot, 'configurator', 'public');
const token = args['--token'] || randomBytes(24).toString('hex');
const listenPort = Number(args['--port'] || 0);
const tasks = new Map();

async function readConfig() {
  if (!existsSync(configFile)) return starterConfig();
  return JSON.parse(await readFile(configFile, 'utf8'));
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
  if (!existsSync(machineFile)) return { version: 1, displayBindings: {} };
  const value = JSON.parse(await readFile(machineFile, 'utf8'));
  return { version: 1, displayBindings: value.displayBindings || {} };
}

function json(response, status, body) {
  response.writeHead(status, { 'content-type': 'application/json; charset=utf-8', 'cache-control': 'no-store', 'x-content-type-options': 'nosniff', 'x-frame-options': 'DENY' });
  response.end(JSON.stringify(body));
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
  await mkdir(dirname(path), { recursive: true, mode: 0o700 });
  if (existsSync(path)) await copyFile(path, `${path}.backup`);
  const temporary = `${path}.tmp-${process.pid}`;
  await writeFile(temporary, value, { mode: 0o600 });
  await rename(temporary, path);
}

async function activity(level, event, details = {}) {
  await mkdir(dirname(activityFile), { recursive: true, mode: 0o700 });
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

function classifyTopology(displays) {
  const active = displays.filter((display) => display['is-visible'] !== false);
  const builtIn = active.find((display) => display['is-built-in'] || /built.?in/i.test(display.label || ''));
  const external = active.filter((display) => display !== builtIn);
  if (!builtIn && external.length) return external.length > 1 ? 'dual_external' : 'clamshell';
  if (!external.length) return 'solo';
  if (external.length > 1) return 'dual_external';
  const item = external[0]; const frame = item.frame || {};
  const orientation = Number(frame.h || item.height || 0) > Number(frame.w || item.width || 0) ? 'tall' : 'wide';
  const side = Number(frame.x || 0) < Number(builtIn?.frame?.x || 0) ? 'left' : 'right';
  return `${orientation}_${side}`;
}

async function queryDisplays() {
  try { const { stdout } = await execFileAsync('yabai', ['-m', 'query', '--displays'], { timeout: 2500, maxBuffer: 1_000_000 }); return { displays: JSON.parse(stdout) }; }
  catch (error) { return { displays: [], unavailable: true, message: error.message }; }
}

function parseSkhdShortcutLine(line, source, config) {
  const match = line.match(/^\s*(.*?)\s*:\s*fish\s+-lc\s+(['"])(.*?)\2\s*$/);
  if (!match) return null;
  const chord = match[1].split(/\s+-\s+/); const key = chord.pop().trim();
  const modifiers = chord.join(' + ').split('+').map((item) => item.trim()).filter(Boolean).map((item) => ({ command: 'cmd', option: 'alt', control: 'ctrl' })[item] || item);
  if (modifiers.some((item) => !['cmd', 'ctrl', 'alt', 'shift', 'fn'].includes(item))) return null;
  const commands = match[3].split(';').map((item) => item.trim()).filter(Boolean);
  const direct = commands.find((command) => /^spacewright\s+run\s+[a-z][a-z0-9_]*\s+(?:solo|tall|wide)$/.test(command));
  const modeCommand = commands.find((command) => /^work_(solo|tall|wide)$/.test(command));
  let action;
  if (direct) { const [, workspace, mode] = direct.match(/^spacewright\s+run\s+([a-z][a-z0-9_]*)\s+(solo|tall|wide)$/); action = { type: 'activateWorkspace', workspace, mode }; }
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

function commandsForExecution(config, payload) {
  const runtime = compileV2(config);
  if (payload.kind === 'mode') {
    if (!['solo', 'wide', 'tall'].includes(payload.target)) throw new Error('unknown mode');
    return { mode: payload.target, commands: [['run', `work_${payload.target}`]] };
  }
  if (payload.kind === 'workspace') {
    if (!config.workspaces[payload.target] || !['solo', 'wide', 'tall'].includes(payload.mode)) throw new Error('unknown workspace or mode');
    if (!config.workspaces[payload.target].variants?.[payload.mode]) throw new Error('workspace has no variant for this mode');
    return { mode: payload.mode, commands: [['run', payload.target, payload.mode]] };
  }
  if (payload.kind === 'profile') {
    const profile = config.profiles?.[payload.target]; if (!profile) throw new Error('unknown profile');
    const workspaceIds = profile.workspaces?.length ? profile.workspaces : config.modes[profile.mode].displays.flatMap((display) => display.workspaceOrder);
    const commands = workspaceIds.map((workspace) => ['run', workspace, profile.mode]);
    if (!commands.length) throw new Error('profile contains no runnable workspaces');
    return { mode: profile.mode, commands };
  }
  throw new Error('kind must be mode, workspace, or profile');
}

async function runTask(task, commands) {
  task.status = 'running'; task.startedAt = new Date().toISOString(); await activity('info', 'task_started', { id: task.id, kind: task.kind, target: task.target });
  for (const commandArgs of commands) {
    if (task.status === 'cancelled') break;
    await new Promise((resolveTask) => {
      const child = spawn(join(packageRoot, 'bin', 'spacewright'), commandArgs, { env: { ...process.env, SPACEWRIGHT_CONFIG_ROOT: configRoot, SPACEWRIGHT_STATE_ROOT: stateRoot }, stdio: ['ignore', 'pipe', 'pipe'] });
      task.child = child; task.logs.push(`$ spacewright ${commandArgs.join(' ')}`);
      const append = (level) => (chunk) => { for (const line of String(chunk).split('\n').filter(Boolean)) task.logs.push(`${level} ${line}`); };
      child.stdout.on('data', append('OUT')); child.stderr.on('data', append('ERR'));
      child.once('error', (error) => { task.logs.push(`ERR ${error.message}`); task.exitCode = 1; resolveTask(); });
      child.once('exit', (code, signal) => { task.exitCode = code ?? (signal ? 130 : 1); task.child = null; resolveTask(); });
    });
    if (task.exitCode !== 0) break;
  }
  if (task.status !== 'cancelled') task.status = task.exitCode === 0 ? 'completed' : 'failed';
  task.finishedAt = new Date().toISOString(); await activity(task.status === 'completed' ? 'info' : 'error', 'task_finished', { id: task.id, status: task.status, exitCode: task.exitCode });
}

function matchingRules(config, context) {
  return (config.rules || []).filter((rule) => rule.enabled && Object.entries(rule.when || {}).every(([key, value]) => key === 'event' ? value === context.event : context[key] === value));
}

async function executeRule(config, rule) {
  const kind = rule.then.activateProfile ? 'profile' : 'workspace'; const target = rule.then.activateProfile || rule.then.activateWorkspace;
  const execution = commandsForExecution(config, { kind, target, mode: rule.then.mode || 'solo' });
  const id = randomBytes(10).toString('hex'); const task = { id, kind, target, mode: execution.mode, status: 'queued', createdAt: new Date().toISOString(), startedAt: null, finishedAt: null, exitCode: null, logs: [`SYSTEM matched rule ${rule.id}`], child: null };
  tasks.set(id, task); void runTask(task, execution.commands); return task;
}

async function archiveConfig() {
  if (!existsSync(configFile)) return;
  const backupRoot = join(configRoot, 'backups');
  await mkdir(backupRoot, { recursive: true, mode: 0o700 });
  await copyFile(configFile, join(backupRoot, `config.v2.${Date.now()}.json`));
  const backups = (await readdir(backupRoot)).filter((name) => /^config\.v2\.[0-9]+\.json$/.test(name)).sort().reverse();
  await Promise.all(backups.slice(10).map((name) => unlink(join(backupRoot, name))));
}

function serializedConfig(config) {
  return `${JSON.stringify(config, null, 2)}\n`;
}

function compiledDocument(config) {
  const source = serializedConfig(config);
  const sourceSha256 = createHash('sha256').update(source).digest('hex');
  return { ...compileV2(config), generated: { format_version: 1, compiler_version: CONFIG_COMPILER_VERSION, source_version: config.version, generation_id: sourceSha256.slice(0, 16), source_sha256: sourceSha256 } };
}

async function api(request, response, url) {
  if (request.method !== 'GET' && request.headers['x-spacewright-token'] !== token) return json(response, 403, { error: 'invalid session token' });
  if (url.pathname === '/api/config' && request.method === 'GET') return json(response, 200, { config: await readConfig(), path: configFile, source: existsSync(configFile) ? 'v2' : 'starter', legacyAvailable: true });
  if (url.pathname === '/api/config-backup' && request.method === 'GET') {
    const backup = `${configFile}.backup`;
    if (!existsSync(backup)) return json(response, 404, { error: 'no configuration backup exists' });
    return json(response, 200, { config: JSON.parse(await readFile(backup, 'utf8')), path: backup });
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
    const candidate = await body(request); const current = await readConfig();
    return json(response, 200, { changes: configDiff(current, candidate), count: configDiff(current, candidate).length });
  }
  if (url.pathname === '/api/save' && request.method === 'POST') {
    const config = await body(request);
    const validation = validateV2(config);
    if (!validation.valid) return json(response, 422, validation);
    const source = serializedConfig(config);
    await archiveConfig();
    await createSnapshot(await readConfig(), 'before-apply');
    await atomicWrite(runtimeFile, `${JSON.stringify(compiledDocument(config), null, 2)}\n`);
    await atomicWrite(configFile, source);
    const readBack = await readConfig();
    if (serializedConfig(readBack) !== source) return json(response, 500, { error: 'read-back verification failed' });
    const snapshot = await createSnapshot(readBack, 'apply');
    await activity('info', 'configuration_saved', { snapshotId: snapshot.id });
    return json(response, 200, { saved: true, verified: true, snapshot, path: configFile, runtimePath: runtimeFile });
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
    const id = url.pathname.split('/')[3]; const path = join(historyRoot, `${id}.json`); if (!existsSync(path)) return json(response, 404, { error: 'snapshot not found' });
    const snapshot = JSON.parse(await readFile(path, 'utf8')); const validation = validateV2(snapshot.config); if (!validation.valid) return json(response, 422, validation);
    await createSnapshot(await readConfig(), 'before-restore'); await atomicWrite(runtimeFile, `${JSON.stringify(compiledDocument(snapshot.config), null, 2)}\n`); await atomicWrite(configFile, serializedConfig(snapshot.config)); await activity('info', 'snapshot_restored', { id });
    return json(response, 200, { restored: true, config: snapshot.config });
  }
  if (url.pathname.startsWith('/api/history/') && request.method === 'DELETE') {
    const id = url.pathname.split('/').at(-1); const path = join(historyRoot, `${id}.json`); if (!existsSync(path)) return json(response, 404, { error: 'snapshot not found' }); await unlink(path); return json(response, 200, { deleted: true });
  }
  if (url.pathname === '/api/preview' && request.method === 'POST') {
    const payload = await body(request); const config = payload.config || await readConfig(); const validation = validateV2(config); if (!validation.valid) return json(response, 422, validation);
    const runtime = compileV2(config); const profile = payload.profile ? config.profiles?.[payload.profile] : null; const mode = profile?.mode || payload.mode || 'solo'; const requested = profile?.workspaces;
    const steps = (runtime.modes[`work_${mode}`]?.steps || []).filter((step) => !requested || !step.workspace || requested.some((id) => step.workspace.includes(id)));
    return json(response, 200, { dryRun: true, mutates: false, mode, profile: payload.profile || null, steps });
  }
  if (url.pathname === '/api/tasks' && request.method === 'GET') return json(response, 200, { tasks: [...tasks.values()].sort((a, b) => b.createdAt.localeCompare(a.createdAt)).slice(0, 50).map(taskView) });
  if (url.pathname === '/api/rules/evaluate' && request.method === 'POST') { const payload = await body(request); const config = await readConfig(); const display = await queryDisplays(); const context = { event: payload.event || 'manual', topology: classifyTopology(display.displays), orientation: classifyTopology(display.displays).startsWith('tall') ? 'tall' : 'wide' }; const rules = matchingRules(config, context); if (!payload.execute) return json(response, 200, { context, matches: rules, mutates: false }); if (payload.confirmed !== true) return json(response, 422, { error: 'explicit execution confirmation is required' }); const launched = []; for (const rule of rules) launched.push(taskView(await executeRule(config, rule))); return json(response, 202, { context, tasks: launched }); }
  if (url.pathname === '/api/execute' && request.method === 'POST') {
    const payload = await body(request); if (payload.confirmed !== true) return json(response, 422, { error: 'explicit execution confirmation is required' });
    const config = await readConfig(); const validation = validateV2(config); if (!validation.valid) return json(response, 422, validation);
    let execution; try { execution = commandsForExecution(config, payload); } catch (error) { return json(response, 422, { error: error.message }); }
    const id = randomBytes(10).toString('hex'); const task = { id, kind: payload.kind, target: payload.target, mode: execution.mode, status: 'queued', createdAt: new Date().toISOString(), startedAt: null, finishedAt: null, exitCode: null, logs: [], child: null };
    tasks.set(id, task); void runTask(task, execution.commands); return json(response, 202, { task: taskView(task) });
  }
  if (url.pathname.match(/^\/api\/tasks\/[a-f0-9]+$/) && request.method === 'GET') { const id = url.pathname.split('/').at(-1); const task = tasks.get(id); return task ? json(response, 200, { task: taskView(task) }) : json(response, 404, { error: 'task not found' }); }
  if (url.pathname.match(/^\/api\/tasks\/[a-f0-9]+\/cancel$/) && request.method === 'POST') { const id = url.pathname.split('/')[3]; const task = tasks.get(id); if (!task) return json(response, 404, { error: 'task not found' }); if (!['queued', 'running'].includes(task.status)) return json(response, 409, { error: 'task is no longer running' }); task.status = 'cancelled'; task.child?.kill('SIGTERM'); task.logs.push('SYSTEM cancellation requested'); return json(response, 200, { task: taskView(task) }); }
  if (url.pathname === '/api/topology' && request.method === 'GET') { const result = await queryDisplays(); return json(response, 200, { ...result, topology: classifyTopology(result.displays), mutates: false }); }
  if (url.pathname === '/api/diagnostics' && request.method === 'GET') {
    const config = await readConfig(); const validation = validateV2(config); const display = await queryDisplays(); const yabai = await commandCheck('yabai');
    const checks = [{ id: 'yabai', ok: yabai.ok, detail: yabai.detail }, { id: 'accessibility', ok: yabai.ok, detail: yabai.ok ? 'yabai can query the window server' : 'unavailable' }, { id: 'scripting_addition', ok: yabai.ok, detail: 'validated through yabai availability' }, { id: 'display', ok: display.displays.length > 0, detail: `${display.displays.length} detected` }, { id: 'backend', ok: true, detail: 'local authenticated server' }, { id: 'schema', ok: validation.valid, detail: validation.valid ? 'valid' : validation.errors.join('; ') }, { id: 'workspace', ok: Object.keys(config.workspaces || {}).length > 0, detail: `${Object.keys(config.workspaces || {}).length} configured` }];
    return json(response, 200, { generatedAt: new Date().toISOString(), topology: classifyTopology(display.displays), checks });
  }
  if (url.pathname === '/api/self-test' && request.method === 'POST') { const config = await readConfig(); const validation = validateV2(config); const compiled = validation.valid ? compileV2(config) : null; await activity(validation.valid ? 'info' : 'error', 'self_test', { valid: validation.valid }); return json(response, validation.valid ? 200 : 422, { valid: validation.valid, errors: validation.errors, compiled: Boolean(compiled), mutates: false }); }
  if (url.pathname === '/api/activity' && request.method === 'GET') { const lines = existsSync(activityFile) ? (await readFile(activityFile, 'utf8')).trim().split('\n').filter(Boolean).slice(-200).reverse().map(JSON.parse) : []; return json(response, 200, { entries: lines }); }
  if (url.pathname === '/api/import' && request.method === 'POST') { const payload = await body(request); let config; try { config = YAML.parse(payload.text); } catch (error) { return json(response, 422, { error: `YAML parse failed: ${error.message}` }); } const validation = validateV2(config); return json(response, validation.valid ? 200 : 422, { ...validation, config }); }
  if (url.pathname === '/api/export' && request.method === 'GET') { response.writeHead(200, { 'content-type': 'application/yaml; charset=utf-8', 'content-disposition': 'attachment; filename="spacewright.yaml"', 'cache-control': 'no-store' }); return response.end(YAML.stringify(await readConfig())); }
  if (url.pathname === '/api/restore-backup' && request.method === 'POST') {
    const backup = `${configFile}.backup`;
    if (!existsSync(backup)) return json(response, 404, { error: 'no configuration backup exists' });
    const config = JSON.parse(await readFile(backup, 'utf8'));
    const validation = validateV2(config);
    if (!validation.valid) return json(response, 422, { error: 'the configuration backup is invalid', ...validation });
    await atomicWrite(runtimeFile, `${JSON.stringify(compiledDocument(config), null, 2)}\n`);
    await atomicWrite(configFile, serializedConfig(config));
    return json(response, 200, { restored: true, config, path: configFile, runtimePath: runtimeFile });
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
    const config = payload.config || await readConfig();
    if (payload.config) {
      const validation = validateV2(config);
      if (!validation.valid) return json(response, 422, { error: 'candidate configuration is invalid', ...validation });
    }
    if (!payload.displayBindings || typeof payload.displayBindings !== 'object' || Array.isArray(payload.displayBindings)) return json(response, 422, { error: 'displayBindings must be an object' });
    for (const [role, uuid] of Object.entries(payload.displayBindings)) {
      if (!config.displayRoles[role]) return json(response, 422, { error: `unknown display role: ${role}` });
      if (typeof uuid !== 'string' || !/^[A-Za-z0-9-]{8,}$/.test(uuid)) return json(response, 422, { error: `invalid display UUID for ${role}` });
    }
    const uuids = Object.values(payload.displayBindings);
    if (new Set(uuids).size !== uuids.length) return json(response, 422, { error: 'one display UUID cannot be bound to multiple roles' });
    const machine = { version: 1, displayBindings: payload.displayBindings };
    await atomicWrite(machineFile, `${JSON.stringify(machine, null, 2)}\n`);
    return json(response, 200, { saved: true, machine, path: machineFile });
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
const server = http.createServer(async (request, response) => {
  try {
    const url = new URL(request.url, 'http://127.0.0.1');
    if (url.pathname.startsWith('/api/')) return await api(request, response, url);
    const relative = url.pathname === '/' ? 'index.html' : url.pathname.slice(1);
    if (relative.includes('..')) return json(response, 400, { error: 'invalid path' });
    const content = await readFile(join(publicRoot, relative));
    response.writeHead(200, {
      'content-type': mime[extname(relative)] || 'application/octet-stream',
      'cache-control': 'no-store',
      'content-security-policy': "default-src 'self'; script-src 'self'; style-src 'self' 'unsafe-inline'; connect-src 'self'; img-src 'self' data:; frame-ancestors 'none'",
      'x-content-type-options': 'nosniff',
      'x-frame-options': 'DENY'
    });
    response.end(content);
  } catch (error) {
    if (error.code === 'ENOENT') return json(response, 404, { error: 'not found' });
    json(response, 500, { error: error.message });
  }
});

server.listen(listenPort, '127.0.0.1', () => {
  const { port } = server.address();
  const url = `http://127.0.0.1:${port}/?token=${token}`;
  process.stdout.write(`SPACEWRIGHT_CONFIGURATOR_URL=${url}\n`);
  if (!process.argv.includes('--no-open')) execFile('open', [url], () => {});
});

let lastTopology;
setInterval(async () => {
  try {
    const display = await queryDisplays(); const topology = classifyTopology(display.displays);
    if (lastTopology == null) { lastTopology = topology; return; }
    if (topology === lastTopology) return;
    const previous = lastTopology; lastTopology = topology; const config = await readConfig();
    await activity('info', 'topology_changed', { previous, topology });
    if (config.settings?.eventAutomationEnabled !== true) return;
    const event = topology === 'solo' || topology === 'clamshell' ? 'display_disconnected' : previous === 'solo' || previous === 'clamshell' ? 'display_connected' : 'topology_changed';
    const context = { event, topology, orientation: topology.startsWith('tall') ? 'tall' : 'wide' };
    for (const rule of matchingRules(config, context)) await executeRule(config, rule);
  } catch (error) { await activity('error', 'topology_monitor_failed', { message: error.message }); }
}, 5000).unref();
