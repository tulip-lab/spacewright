#!/usr/bin/env node
import { normalizeSnapshot } from './lib/state-engine.mjs';
import { selectRole } from './lib/window-policy.mjs';
import { readFile } from 'node:fs/promises';
import { join } from 'node:path';
import { acquireExecution, runBounded, verifyLease, processIdentity } from './lib/execution-coordinator.mjs';
const [action, executable, ...args] = process.argv.slice(2);
const stateRoot = process.env.SPACEWRIGHT_STATE_ROOT;
try {
  if (action === 'select') {
    const value = JSON.parse(await readFile('/dev/stdin', 'utf8'));
    const role = value.plan.windows[value.index];
    const selected = selectRole(normalizeSnapshot({windows:value.windows}).windows, { ...role, allowNativeFullscreen:value.plan.preparation === true, appNames: role.app_names || [], bundleIds: role.bundle_ids || [] }, {used:value.used || [], targetSpace:value.targetSpace});
    if (selected.ambiguous) { if (role.required) throw new Error('required window match is ambiguous'); }
    else for (const window of selected.selected) process.stdout.write(`${window.id}\n`);
  } else if (action === 'verify') {
    if (!stateRoot || !await verifyLease(stateRoot)) throw new Error('execution ownership is not valid');
  } else if (action === 'exec') {
    const deadline = Number(process.env.SPACEWRIGHT_EXECUTION_DEADLINE_MS) || Date.now() + 120000;
    const lease = await acquireExecution(stateRoot, { controller: 'direct', deadlineAt: new Date(deadline).toISOString() });
    const abort = new AbortController();
    for (const sig of ['SIGTERM', 'SIGINT']) process.once(sig, () => abort.abort(Object.assign(new Error('cancelled'), { code: 'SPACEWRIGHT_CANCELLED' })));
    try {
      const result = await runBounded(executable, args, { env: { ...process.env, ...lease.env }, deadline, signal: abort.signal,
        onChild: lease.trackChild, onOutput: (stream, value) => process[stream].write(value) });
      process.exitCode = result.code;
    } finally { await lease.release(); }
  } else if (action === 'window-check') {
    if (!await verifyLease(stateRoot)) throw new Error('execution ownership is not valid');
    const envelope = JSON.parse(await readFile(process.env.SPACEWRIGHT_EXECUTION_ENVELOPE, 'utf8'));
    const expected = envelope.plan.selectedWindows.find((w) => w.id === Number(executable));
    const current = JSON.parse(await readFile('/dev/stdin', 'utf8'));
    if (!expected || current.id !== expected.id || current.app !== expected.app || Number(current.pid || 0) !== expected.pid || String(current['bundle-id'] || '') !== expected.bundleId) throw new Error(`planned window ${executable} identity changed; replan required`);
    if (expected.processFingerprint && await processIdentity(expected.pid) !== expected.processFingerprint) throw new Error('planned application process lifetime changed; replan required');
    const s = expected.selector;
    if (current['is-minimized'] || current['is-native-fullscreen'] || s.movable && !current['can-move'] || s.visible && current['is-visible'] === false
      || s.non_empty_title && !current.title || s.title_include && !String(current.title || '').includes(s.title_include)
      || s.title_exclude && String(current.title || '').includes(s.title_exclude) || s.role && current.role !== s.role || s.subrole && current.subrole !== s.subrole) throw new Error(`planned window ${executable} precondition changed; replan required`);
  } else throw new Error('unknown execution coordination action');
} catch (error) { process.stderr.write(`SpaceWright: ${error.message}\n`); process.exitCode = error.code === 'SPACEWRIGHT_CANCELLED' ? 130 : error.code === 'SPACEWRIGHT_TIMEOUT' ? 124 : 1; }
