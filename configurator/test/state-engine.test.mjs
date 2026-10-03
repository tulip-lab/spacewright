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

test('profile orchestration still applies display and final focus when layout is converged', () => {
  const config = starterConfig();
  config.profiles = { focused: { name: 'Focused', mode: 'solo', workspaces: ['coding'], displayConfig: { profile: 'solo' }, focusBehaviour: { workspace: 'coding' }, settings: { reconcile: true } } };
  const snapshot = fixture();
  const state = buildDesiredState(config, compileV2(config), { kind: 'profile', id: 'focused' });
  const comparison = compareState(snapshot, state, { displayBindings: { primary: 'DISPLAY-PRIMARY' } });
  assert.equal(comparison.converged, true);
  const plan = buildExecutionPlan(snapshot, state, comparison, { createdAt: '2026-10-02T00:00:00.000Z' });
  assert.deepEqual(plan.actions, [
    { type: 'apply_display_profile', profile: 'solo' },
    { type: 'focus_workspace', workspaceId: 'coding', mode: 'solo' },
    { type: 'verify', target: { kind: 'profile', id: 'focused', mode: 'solo' } }
  ]);
  assert.deepEqual(plan.runnerCommands, [['display', 'solo'], ['focus', 'coding', 'solo']]);
});

test('profile focus mismatch creates a focus-only plan', () => {
  const config = starterConfig();
  config.profiles = { focused: { name: 'Focused', mode: 'solo', workspaces: ['coding'], focusBehaviour: { workspace: 'coding' } } };
  const snapshot = fixture();
  snapshot.spaces[0].focused = false;
  const state = buildDesiredState(config, compileV2(config), { kind: 'profile', id: 'focused' });
  const comparison = compareState(snapshot, state, { displayBindings: { primary: 'DISPLAY-PRIMARY' } });
  assert.ok(comparison.drifts.some((item) => item.code === 'workspace_focus_mismatch'));
  const plan = buildExecutionPlan(snapshot, state, comparison, { createdAt: '2026-10-02T00:00:00.000Z' });
  assert.deepEqual(plan.runnerCommands, [['focus', 'coding', 'solo']]);
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

test('aggregate comparison assigns shared apps to the last active workspace', () => {
  const snapshot = normalizeSnapshot({
    capturedAt: '2026-10-02T00:00:00.000Z',
    displays: [{ index: 1, uuid: 'DISPLAY-PRIMARY', frame: { x: 0, y: 0, w: 1200, h: 900 }, spaces: [1, 2] }],
    spaces: [
      { index: 1, uuid: 'SPACE-REVIEW', display: 1, label: 'review_wide', type: 'float' },
      { index: 2, uuid: 'SPACE-CODING', display: 1, label: 'coding_wide', type: 'float' }
    ],
    windows: [
      { id: 10, app: 'Finder', display: 1, space: 1, frame: { x: 0, y: 0, w: 1200, h: 900 }, 'can-move': true },
      { id: 11, app: 'Code', display: 1, space: 2, frame: { x: 600, y: 0, w: 600, h: 900 }, 'can-move': true },
      { id: 12, app: 'ChatGPT', display: 1, space: 2, frame: { x: 0, y: 0, w: 600, h: 900 }, 'can-move': true }
    ]
  });
  const desiredState = {
    desiredStateId: 'SHARED', target: { kind: 'mode', id: 'wide', mode: 'wide' },
    orchestration: { displayProfile: null, focusWorkspace: null, reconcile: true },
    workspaces: [
      { workspaceId: 'review', label: 'review_wide', displayRole: 'primary', runner: 'gtd_review', layout: [{ role: 'finder', grid: '1:1:0:0:1:1' }, { role: 'assistant', grid: '1:1:0:0:1:1' }], windows: [
        { role: 'finder', appKey: 'finder', appNames: ['Finder'], bundleIds: [], required: false, selector: {} },
        { role: 'assistant', appKey: 'chatgpt', appNames: ['ChatGPT'], bundleIds: [], required: false, selector: {} }
      ] },
      { workspaceId: 'coding', label: 'coding_wide', displayRole: 'primary', runner: 'generic_layout', layout: [{ role: 'editor', grid: '1:2:1:0:1:1' }, { role: 'assistant', grid: '1:2:0:0:1:1' }], windows: [
        { role: 'editor', appKey: 'code', appNames: ['Code'], bundleIds: [], required: true, selector: {} },
        { role: 'assistant', appKey: 'chatgpt', appNames: ['ChatGPT'], bundleIds: [], required: false, selector: {} }
      ] }
    ]
  };
  const comparison = compareState(snapshot, desiredState, { displayBindings: { primary: 'DISPLAY-PRIMARY' } });
  assert.equal(comparison.converged, true);
  assert.equal(comparison.matches.find((item) => item.workspaceId === 'review' && item.role === 'assistant').supersededByWorkspaceId, 'coding');
  assert.equal(comparison.matches.find((item) => item.workspaceId === 'coding' && item.role === 'assistant').selectedWindowId, 12);
  assert.equal(buildExecutionPlan(snapshot, desiredState, comparison).actions.length, 0);
});

test('office workspaces without their primary document stay inactive', () => {
  const snapshot = fixture();
  const desiredState = {
    desiredStateId: 'OFFICE-IDLE', target: { kind: 'mode', id: 'wide', mode: 'wide' },
    workspaces: [{
      workspaceId: 'slides', label: 'slides_wide', displayRole: 'primary', runner: 'office_document',
      layout: [{ role: 'primary', grid: '1:2:1:0:1:1' }, { role: 'helper', grid: '1:2:0:0:1:1' }],
      windows: [
        { role: 'primary', appKey: 'powerpoint', appNames: ['Microsoft PowerPoint'], bundleIds: [], required: false, selector: {} },
        { role: 'helper', appKey: 'chatgpt', appNames: ['ChatGPT'], bundleIds: [], required: false, selector: {} }
      ]
    }]
  };
  const comparison = compareState(snapshot, desiredState, { displayBindings: { primary: 'DISPLAY-PRIMARY' } });
  assert.equal(comparison.converged, true);
  assert.ok(comparison.drifts.some((item) => item.code === 'workspace_inactive' && item.severity === 'warning'));
  assert.ok(!comparison.drifts.some((item) => item.code === 'space_missing'));
});

test('declarative multi-window roles select every match without false ambiguity or geometry drift', () => {
  const snapshot = normalizeSnapshot({
    displays: [{ index: 1, uuid: 'DISPLAY-PRIMARY', frame: { x: 0, y: 0, w: 1200, h: 900 }, spaces: [1] }],
    spaces: [{ index: 1, uuid: 'SPACE-SUPPORT', display: 1, label: 'support_wide', type: 'float' }],
    windows: [
      { id: 20, app: 'Dia', display: 1, space: 1, frame: { x: 0, y: 0, w: 600, h: 450 }, 'can-move': true },
      { id: 21, app: 'Dia', display: 1, space: 1, frame: { x: 600, y: 0, w: 600, h: 900 }, 'can-move': true },
      { id: 22, app: 'Dia', display: 1, space: 1, frame: { x: 0, y: 450, w: 600, h: 450 }, 'can-move': true }
    ]
  });
  const desiredState = {
    desiredStateId: 'DIA', target: { kind: 'workspace', id: 'support', mode: 'wide' },
    workspaces: [{ workspaceId: 'support', label: 'support_wide', displayRole: 'primary', runner: 'gtd_support', layout: [{ role: 'dia', grid: '1:2:0:0:1:1' }], windows: [
      { role: 'dia', appKey: 'dia', appNames: ['Dia'], bundleIds: [], required: false, selector: {} }
    ] }]
  };
  const comparison = compareState(snapshot, desiredState, { displayBindings: { primary: 'DISPLAY-PRIMARY' } });
  assert.equal(comparison.converged, true);
  assert.deepEqual(comparison.matches[0].selectedWindowIds, [20, 21, 22]);
  assert.ok(!comparison.drifts.some((item) => item.code === 'window_match_ambiguous'));
  assert.ok(!comparison.drifts.some((item) => item.code === 'window_geometry_mismatch'));
  const single = structuredClone(snapshot);
  single.windows = [single.windows[0]];
  const singleComparison = compareState(single, desiredState, { displayBindings: { primary: 'DISPLAY-PRIMARY' } });
  assert.ok(!singleComparison.drifts.some((item) => item.code === 'window_geometry_mismatch'));
});

test('independent ownership lets distinct selectors assign one app to different workspaces', () => {
  const snapshot = normalizeSnapshot({
    displays: [{ index: 1, uuid: 'DISPLAY-PRIMARY', frame: { x: 0, y: 0, w: 1200, h: 900 }, spaces: [1, 2] }],
    spaces: [
      { index: 1, uuid: 'SPACE-A', display: 1, label: 'a_wide', type: 'float' },
      { index: 2, uuid: 'SPACE-B', display: 1, label: 'b_wide', type: 'float' }
    ],
    windows: [
      { id: 31, app: 'Browser', title: 'Alpha', display: 1, space: 1, frame: { x: 0, y: 0, w: 1200, h: 900 }, 'can-move': true },
      { id: 32, app: 'Browser', title: 'Beta', display: 1, space: 2, frame: { x: 0, y: 0, w: 1200, h: 900 }, 'can-move': true }
    ]
  });
  const window = (role, title) => ({ role, appKey: 'browser', appNames: ['Browser'], bundleIds: [], required: true, ownership: 'independent', cardinality: 'one', selector: { title_include: title } });
  const desiredState = {
    desiredStateId: 'INDEPENDENT', target: { kind: 'mode', id: 'wide', mode: 'wide' },
    workspaces: [
      { workspaceId: 'a', label: 'a_wide', displayRole: 'primary', layout: [{ role: 'browser_a', grid: '1:1:0:0:1:1' }], windows: [window('browser_a', 'Alpha')] },
      { workspaceId: 'b', label: 'b_wide', displayRole: 'primary', layout: [{ role: 'browser_b', grid: '1:1:0:0:1:1' }], windows: [window('browser_b', 'Beta')] }
    ]
  };
  const comparison = compareState(snapshot, desiredState, { displayBindings: { primary: 'DISPLAY-PRIMARY' } });
  assert.equal(comparison.converged, true);
  assert.deepEqual(comparison.matches.map((item) => item.selectedWindowId), [31, 32]);
});

test('aggregate comparison reports actual Space order drift', () => {
  const snapshot = normalizeSnapshot({
    displays: [{ index: 1, uuid: 'DISPLAY-PRIMARY', frame: { x: 0, y: 0, w: 1200, h: 900 }, spaces: [1, 2] }],
    spaces: [
      { index: 1, uuid: 'SPACE-B', display: 1, label: 'b_wide', type: 'float' },
      { index: 2, uuid: 'SPACE-A', display: 1, label: 'a_wide', type: 'float' }
    ], windows: []
  });
  const desiredState = {
    desiredStateId: 'ORDER', target: { kind: 'mode', id: 'wide', mode: 'wide' },
    orchestration: { displayProfile: null, focusWorkspace: null, reconcile: true },
    workspaces: [
      { workspaceId: 'a', label: 'a_wide', displayRole: 'primary', runner: 'generic_layout', layout: [], windows: [] },
      { workspaceId: 'b', label: 'b_wide', displayRole: 'primary', runner: 'generic_layout', layout: [], windows: [] }
    ]
  };
  const comparison = compareState(snapshot, desiredState, { displayBindings: { primary: 'DISPLAY-PRIMARY' } });
  assert.ok(comparison.drifts.some((item) => item.code === 'space_order_mismatch'));
  assert.deepEqual(buildExecutionPlan(snapshot, desiredState, comparison).actions, [
    { type: 'order_spaces', mode: 'wide' },
    { type: 'verify', target: { kind: 'mode', id: 'wide', mode: 'wide' } }
  ]);
  assert.deepEqual(buildExecutionPlan(snapshot, desiredState, comparison).runnerCommands, [['order', 'wide']]);
});

test('aggregate execution runs only workspaces with change drift', () => {
  const snapshot = fixture({ helperX: 50 });
  const { config, runtime } = desired();
  config.modes.solo.postprocessors = [{ name: 'gtd_ai_expand_hermes_when_alone', afterCommand: 'spacewright_coding_solo' }];
  const state = buildDesiredState(config, runtime, { kind: 'mode', id: 'solo', mode: 'solo' });
  const comparison = compareState(snapshot, state, { displayBindings: { primary: 'DISPLAY-PRIMARY' } });
  const plan = buildExecutionPlan(snapshot, state, comparison, { createdAt: '2026-10-02T00:00:00.000Z' });
  assert.deepEqual(plan.runnerCommands, [['run', 'coding', 'solo'], ['postprocess', 'gtd_ai_expand_hermes_when_alone']]);
  assert.ok(!plan.runnerCommands.some((command) => command[1] === 'work_solo'));
});

test('comparison recovers a uniquely identifiable unlabeled Space', () => {
  const snapshot = normalizeSnapshot({
    displays: [{ index: 1, uuid: 'DISPLAY-PRIMARY', frame: { x: 0, y: 0, w: 1200, h: 900 }, spaces: [1] }],
    spaces: [{ index: 1, uuid: 'SPACE-UNLABELED', display: 1, label: '', type: 'float' }],
    windows: [{ id: 10, app: 'Code', display: 1, space: 1, frame: { x: 0, y: 0, w: 1200, h: 900 }, 'can-move': true }]
  });
  const { desired: state } = desired();
  const comparison = compareState(snapshot, state, { displayBindings: { primary: 'DISPLAY-PRIMARY' } });
  assert.ok(comparison.drifts.some((item) => item.code === 'space_label_missing' && item.spaceUuid === 'SPACE-UNLABELED'));
  assert.ok(!comparison.drifts.some((item) => item.code === 'space_missing'));
  assert.ok(buildExecutionPlan(snapshot, state, comparison).actions.some((action) => action.type === 'recover_space_label' && action.spaceIndex === 1));
});
