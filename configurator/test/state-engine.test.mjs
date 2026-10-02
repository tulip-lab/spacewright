import test from 'node:test';
import assert from 'node:assert/strict';
import { buildDesiredState, buildExecutionPlan, captureWorkspace, compareState, normalizeSnapshot } from '../lib/state-engine.mjs';
import { compileV2, starterConfig } from '../lib/config-v2.mjs';

function fixture({ helperSpace = 1, helperX = 600 } = {}) {
  return normalizeSnapshot({
    capturedAt: '2026-10-02T00:00:00.000Z',
    displays: [{ index: 1, uuid: 'DISPLAY-PRIMARY', frame: { x: 0, y: 0, w: 1200, h: 900 }, 'is-built-in': true, 'has-focus': true, spaces: [1] }],
    spaces: [{ index: 1, uuid: 'SPACE-CODING', display: 1, label: 'coding_solo', type: 'float', 'has-focus': true }],
    windows: [
      { id: 10, pid: 100, app: 'Code', title: 'Project', role: 'AXWindow', subrole: 'AXStandardWindow', display: 1, space: 1, frame: { x: 0, y: 0, w: helperX === 600 ? 1200 : 600, h: 900 }, 'can-move': true, 'can-resize': true, 'is-visible': true },
      { id: 11, pid: 101, app: 'ChatGPT', title: 'Chat', role: 'AXWindow', subrole: 'AXStandardWindow', display: 1, space: helperSpace, frame: { x: 600, y: 0, w: 600, h: 900 }, 'can-move': true, 'can-resize': true, 'is-visible': true }
    ]
  }, { displayBindings: { primary: 'DISPLAY-PRIMARY' } });
}

function desired() {
  const config = starterConfig();
  const runtime = compileV2(config);
  return { config, runtime, desired: buildDesiredState(config, runtime, { kind: 'workspace', id: 'coding', mode: 'solo' }) };
}

test('snapshot normalization is deterministic apart from capture time', () => {
  const first = fixture();
  const second = fixture();
  assert.equal(first.snapshotId, second.snapshotId);
  assert.equal(first.displays[0].role, 'primary');
  assert.deepEqual(first.spaces[0].windows, [10, 11]);
});

test('comparison reports a converged workspace', () => {
  const snapshot = fixture();
  const { desired: state } = desired();
  const comparison = compareState(snapshot, state, { displayBindings: { primary: 'DISPLAY-PRIMARY' } });
  assert.equal(comparison.counts.blocker, 0);
  assert.equal(comparison.counts.change, 0);
  assert.equal(comparison.converged, true);
});

test('plan reports live move and resize actions without mutating', () => {
  const snapshot = fixture({ helperSpace: 2, helperX: 50 });
  const { desired: state } = desired();
  const comparison = compareState(snapshot, state, { displayBindings: { primary: 'DISPLAY-PRIMARY' } });
  const plan = buildExecutionPlan(snapshot, state, comparison, { createdAt: '2026-10-02T00:00:00.000Z' });
  assert.equal(plan.executable, true);
  assert.ok(plan.actions.some((action) => action.type === 'move_window' && action.windowId === 11));
  assert.ok(plan.actions.some((action) => action.type === 'resize_window' && action.windowId === 10));
  assert.deepEqual(plan.runnerCommands, [['run', 'coding', 'solo']]);
});

test('missing required windows block execution while optional windows warn', () => {
  const snapshot = fixture();
  snapshot.windows = [];
  snapshot.spaces[0].windows = [];
  snapshot.snapshotId = 'EMPTY';
  const { desired: state } = desired();
  const comparison = compareState(snapshot, state, { displayBindings: { primary: 'DISPLAY-PRIMARY' } });
  assert.ok(comparison.drifts.some((item) => item.code === 'required_window_missing' && item.severity === 'blocker'));
  assert.ok(comparison.drifts.some((item) => item.code === 'optional_window_missing' && item.severity === 'warning'));
  assert.equal(buildExecutionPlan(snapshot, state, comparison).executable, false);
});

test('capture produces a validated-shape canvas draft without writing configuration', () => {
  const captured = captureWorkspace(fixture(), { workspaceId: 'captured_coding', name: 'Captured Coding', mode: 'wide' });
  assert.equal(captured.draft.workspaceId, 'captured_coding');
  assert.equal(captured.draft.workspace.variants.wide.layout.type, 'canvas');
  assert.equal(captured.draft.workspace.variants.wide.layout.regions.length, 2);
  assert.deepEqual(Object.keys(captured.draft.apps), ['code', 'chatgpt']);
});

test('desired state keeps mode-specific variants when historical command ids are shared', () => {
  const config = starterConfig();
  config.workspaces.coding.variants.solo.command = 'coding_shared';
  config.workspaces.coding.variants.wide.command = 'coding_shared';
  config.workspaces.coding.variants.solo.spaceLabel = 'coding_solo_exact';
  config.workspaces.coding.variants.wide.spaceLabel = 'coding_wide_exact';
  const runtime = compileV2(config);
  const solo = buildDesiredState(config, runtime, { kind: 'workspace', id: 'coding', mode: 'solo' });
  const wide = buildDesiredState(config, runtime, { kind: 'workspace', id: 'coding', mode: 'wide' });
  assert.equal(solo.workspaces[0].label, 'coding_solo_exact');
  assert.equal(wide.workspaces[0].label, 'coding_wide_exact');
  assert.notDeepEqual(solo.workspaces[0].layout, wide.workspaces[0].layout);
});

test('profile plans carry closed display, workspace, focus, and recovery commands', () => {
  const config = starterConfig();
  config.profiles = { focused: { name: 'Focused', mode: 'solo', workspaces: ['coding'], displayConfig: { profile: 'solo' }, focusBehaviour: { workspace: 'coding' }, settings: { reconcile: false } } };
  const snapshot = fixture({ helperX: 50 });
  const state = buildDesiredState(config, compileV2(config), { kind: 'profile', id: 'focused' });
  const comparison = compareState(snapshot, state, { displayBindings: { primary: 'DISPLAY-PRIMARY' } });
  const plan = buildExecutionPlan(snapshot, state, comparison, { createdAt: '2026-10-02T00:00:00.000Z' });
  assert.deepEqual(plan.runnerCommands, [['display', 'solo'], ['run', 'coding', 'solo'], ['focus', 'coding', 'solo']]);
  assert.equal(plan.recovery.automaticAttempts, 0);
  assert.deepEqual(plan.recovery.windowIds, [10, 11]);
});

test('AX role selectors reject a mismatched window while bundle ids fall back when unavailable', () => {
  const config = starterConfig();
  config.apps.code.match.bundleIds = ['com.microsoft.VSCode'];
  config.workspaces.coding.windows.editor.selector = { movable: true, role: 'AXDialog' };
  const snapshot = fixture();
  const state = buildDesiredState(config, compileV2(config), { kind: 'workspace', id: 'coding', mode: 'solo' });
  const comparison = compareState(snapshot, state, { displayBindings: { primary: 'DISPLAY-PRIMARY' } });
  assert.ok(comparison.drifts.some((item) => item.code === 'required_window_missing'));
  assert.ok(comparison.matches.find((item) => item.role === 'editor').rejected.some((item) => item.reasons.includes('role')));
});
