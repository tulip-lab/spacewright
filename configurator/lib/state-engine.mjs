import { createHash } from 'node:crypto';
import { compileLayout } from './config-v2.mjs';

export const STATE_FORMAT_VERSION = 1;
export const PLAN_FORMAT_VERSION = 1;

const MODES = new Set(['solo', 'wide', 'tall']);
const clone = (value) => structuredClone(value);
const number = (value, fallback = 0) => Number.isFinite(Number(value)) ? Number(value) : fallback;
const truthy = (value) => value === true;
const digest = (value) => createHash('sha256').update(typeof value === 'string' ? value : JSON.stringify(value)).digest('hex');

function frame(value = {}) {
  return { x: number(value.x), y: number(value.y), w: number(value.w), h: number(value.h) };
}

function normalizedWindow(window) {
  return {
    id: number(window.id),
    pid: number(window.pid),
    app: String(window.app || ''),
    bundleId: String(window['bundle-id'] || window.bundleId || ''),
    title: String(window.title || ''),
    role: String(window.role || ''),
    subrole: String(window.subrole || ''),
    display: number(window.display),
    space: number(window.space),
    frame: frame(window.frame),
    movable: truthy(window['can-move']),
    resizable: truthy(window['can-resize']),
    visible: window['is-visible'] !== false,
    minimized: truthy(window['is-minimized']),
    hidden: truthy(window['is-hidden']),
    sticky: truthy(window['is-sticky']),
    nativeFullscreen: truthy(window['is-native-fullscreen']),
    hasAxReference: window['has-ax-reference'] !== false
  };
}

export function normalizeSnapshot(raw = {}, machine = {}) {
  const bindings = machine.displayBindings || {};
  const boundRoles = new Map(Object.entries(bindings).map(([role, uuid]) => [uuid, role]));
  const displays = (raw.displays || []).map((display) => ({
    index: number(display.index),
    uuid: String(display.uuid || ''),
    role: boundRoles.get(display.uuid) || null,
    label: String(display.label || display.name || ''),
    frame: frame(display.frame),
    builtIn: truthy(display['is-built-in']),
    visible: display['is-visible'] !== false,
    focused: truthy(display['has-focus']),
    spaces: (display.spaces || []).map(number)
  })).sort((a, b) => a.index - b.index);
  const windows = (raw.windows || []).map(normalizedWindow).sort((a, b) => a.id - b.id);
  const windowsBySpace = new Map();
  for (const window of windows) {
    const items = windowsBySpace.get(window.space) || [];
    items.push(window.id);
    windowsBySpace.set(window.space, items);
  }
  const spaces = (raw.spaces || []).map((space) => ({
    index: number(space.index),
    uuid: String(space.uuid || ''),
    display: number(space.display),
    label: String(space.label || ''),
    layout: String(space.type || space.layout || ''),
    focused: truthy(space['has-focus']),
    visible: space['is-visible'] !== false,
    windows: windowsBySpace.get(number(space.index)) || []
  })).sort((a, b) => a.index - b.index);
  const unavailable = Boolean(raw.unavailable);
  const snapshotCore = { formatVersion: STATE_FORMAT_VERSION, unavailable, displays, spaces, windows };
  return {
    ...snapshotCore,
    snapshotId: digest(snapshotCore).slice(0, 20),
    capturedAt: raw.capturedAt || new Date().toISOString(),
    ...(raw.message ? { message: String(raw.message) } : {})
  };
}

function targetDefinition(config, target = {}) {
  const kind = target.kind || (target.workspace ? 'workspace' : target.profile ? 'profile' : 'mode');
  if (kind === 'workspace') {
    const workspaceId = target.id || target.workspace;
    const mode = target.mode;
    if (!config.workspaces?.[workspaceId]) throw new Error(`unknown workspace “${workspaceId}”; choose an id from config.workspaces`);
    if (!MODES.has(mode) || !config.workspaces[workspaceId].variants?.[mode]) throw new Error(`workspace “${workspaceId}” has no ${mode || 'requested'} variant`);
    return { kind, id: workspaceId, mode, workspaceIds: [workspaceId] };
  }
  if (kind === 'profile') {
    const profileId = target.id || target.profile;
    const profile = config.profiles?.[profileId];
    if (!profile) throw new Error(`unknown profile “${profileId}”; choose an id from config.profiles`);
    const workspaceIds = profile.workspaces?.length
      ? [...profile.workspaces]
      : config.modes[profile.mode].displays.flatMap((display) => display.workspaceOrder);
    return { kind, id: profileId, mode: profile.mode, workspaceIds, profile: clone(profile) };
  }
  const mode = target.mode || target.id;
  if (!MODES.has(mode) || !config.modes?.[mode]) throw new Error(`unknown mode “${mode}”; expected solo, wide, or tall`);
  return { kind: 'mode', id: mode, mode, workspaceIds: config.modes[mode].displays.flatMap((display) => display.workspaceOrder) };
}

function sourceWorkspaceId(config, snapshot) {
  const focusedLabel = snapshot?.spaces?.find((space) => space.focused)?.label;
  if (!focusedLabel) return null;
  return Object.entries(config.workspaces || {}).find(([, workspace]) => Object.entries(workspace.variants || {}).some(([mode, variant]) => (
    variant.spaceLabel || `${workspace.spaceLabel}_${mode}`
  ) === focusedLabel))?.[0] || null;
}

export function buildDesiredState(config, runtime, target = {}, snapshot = null) {
  const resolved = targetDefinition(config, target);
  const sourceWorkspace = sourceWorkspaceId(config, snapshot);
  const contextualRules = resolved.kind === 'workspace' ? [] : (runtime.modes?.[`work_${resolved.mode}`]?.contextual_apps || []);
  const sourceRuleIndex = contextualRules.findIndex((rule) => rule.workspace_ids.includes(sourceWorkspace));
  const fallbackFocusIndex = contextualRules.findIndex((rule) => rule.focus_owner === true);
  const focusRuleIndex = sourceRuleIndex >= 0 ? sourceRuleIndex : fallbackFocusIndex;
  const contextualApps = contextualRules.map((rule, index) => ({
    appKey: rule.app_key,
    workspaceIds: clone(rule.workspace_ids),
    ownerWorkspaceId: rule.workspace_ids.includes(sourceWorkspace) ? sourceWorkspace : rule.fallback_workspace_id,
    focusOwner: index === focusRuleIndex
  }));
  const placement = new Map();
  for (const display of config.modes[resolved.mode].displays) for (const workspaceId of display.workspaceOrder) placement.set(workspaceId, display.role);
  const workspaces = resolved.workspaceIds.map((workspaceId) => {
    const workspace = config.workspaces[workspaceId];
    const variant = workspace.variants[resolved.mode];
    const runtimeId = variant.command || `spacewright_${workspaceId}_${resolved.mode}`;
    const configuredWindows = runtime.workspaces?.[runtimeId]?.windows || variant.runtime?.windows || Object.entries(workspace.windows).map(([role, window]) => ({
      role, app_key: window.app, required: window.required,
      ...(window.ownership ? { ownership: window.ownership } : {}),
      ...(window.cardinality ? { cardinality: window.cardinality } : {}),
      ...(window.selector ? { selector: window.selector } : {})
    }));
    const runner = variant.runtime?.runner || 'generic_layout';
    return {
      runtimeId,
      runner,
      workspaceId,
      name: workspace.name,
      mode: resolved.mode,
      label: variant.spaceLabel || `${workspace.spaceLabel}_${resolved.mode}`,
      displayRole: placement.get(workspaceId),
      runtimeDisplayRole: variant.runtime?.displayRole || placement.get(workspaceId),
      activation: clone(variant.activation || (runner === 'office_document' ? { type: 'windowPresent', role: 'primary' } : { type: 'always' })),
      layout: compileLayout(variant.layout),
      windows: configuredWindows.map((window) => {
        const portable = workspace.windows[window.role] || {};
        const appKey = window.app_key || portable.app;
        return {
          role: window.role,
          appKey,
          appNames: clone(config.apps?.[appKey]?.match?.appNames || []),
          bundleIds: clone(config.apps?.[appKey]?.match?.bundleIds || []),
          required: Boolean(window.required),
          ownership: window.ownership || portable.ownership || 'lastApplicable',
          cardinality: window.cardinality || portable.cardinality || (runner === 'gtd_support' && window.role === 'dia' ? 'many' : 'one'),
          selector: clone(window.selector || portable.selector || {})
        };
      })
    };
  });
  const desired = {
    formatVersion: STATE_FORMAT_VERSION,
    target: { kind: resolved.kind, id: resolved.id, mode: resolved.mode },
    workspaces,
    cleanup: clone(runtime.modes?.[`work_${resolved.mode}`]?.cleanup || []),
    postprocessors: clone(config.modes?.[resolved.mode]?.postprocessors || []),
    contextualApps,
    nonoccupyingGhostApps: ['word', 'powerpoint', 'input_source_pro']
      .flatMap((appKey) => config.apps?.[appKey]?.match?.appNames || []),
    orchestration: resolved.profile ? {
      displayProfile: resolved.profile.displayConfig?.profile || null,
      focusWorkspace: resolved.profile.focusBehaviour?.workspace || null,
      reconcile: resolved.profile.settings?.reconcile !== false
    } : {
      displayProfile: null,
      focusWorkspace: contextualApps.find((rule) => rule.focusOwner)?.ownerWorkspaceId || null,
      reconcile: true
    },
    configDigest: digest(config),
    runtimeSourceDigest: runtime.generated?.source_sha256 || null
  };
  return { ...desired, desiredStateId: digest(desired).slice(0, 20) };
}

function selectorResult(window, desired) {
  const selector = desired.selector || {};
  const reasons = [];
  if (desired.appNames.length && !desired.appNames.includes(window.app)) reasons.push('app_name');
  // Standard yabai snapshots do not expose a bundle identifier. Treat bundle IDs
  // as a stronger match only when discovery supplied one, while retaining the
  // portable app-name fallback used by the Fish runtime.
  if (desired.bundleIds?.length && window.bundleId && !desired.bundleIds.includes(window.bundleId)) reasons.push('bundle_id');
  if (selector.movable === true && !window.movable) reasons.push('not_movable');
  if (selector.visible === true && !window.visible) reasons.push('not_visible');
  if (selector.non_empty_title === true && !window.title) reasons.push('empty_title');
  if (selector.title_include && !window.title.includes(selector.title_include)) reasons.push('title_missing_required_text');
  if (selector.title_exclude && window.title.includes(selector.title_exclude)) reasons.push('title_contains_excluded_text');
  if (selector.role && window.role !== selector.role) reasons.push('role');
  if (selector.subrole && window.subrole !== selector.subrole) reasons.push('subrole');
  return { matches: reasons.length === 0, reasons };
}

function parseGrid(value) {
  const parts = String(value || '').split(':').map(Number);
  if (parts.length !== 6 || parts.some((part) => !Number.isFinite(part))) return null;
  const [rows, columns, x, y, width, height] = parts;
  if (rows <= 0 || columns <= 0) return null;
  return { x: x / columns, y: y / rows, w: width / columns, h: height / rows };
}

function normalizedFrame(windowFrame, displayFrame) {
  if (!displayFrame?.w || !displayFrame?.h) return null;
  return {
    x: (windowFrame.x - displayFrame.x) / displayFrame.w,
    y: (windowFrame.y - displayFrame.y) / displayFrame.h,
    w: windowFrame.w / displayFrame.w,
    h: windowFrame.h / displayFrame.h
  };
}

function geometryMatches(window, display, layout, tolerance = 0.055) {
  const expected = parseGrid(layout?.grid);
  const actual = normalizedFrame(window.frame, display?.frame);
  if (!expected || !actual) return { comparable: false, matches: null, expected, actual };
  const delta = Object.fromEntries(['x', 'y', 'w', 'h'].map((key) => [key, Math.abs(expected[key] - actual[key])]));
  return { comparable: true, matches: Object.values(delta).every((value) => value <= tolerance), expected, actual, delta };
}

function drift(code, severity, workspace, details = {}) {
  return { code, severity, workspaceId: workspace.workspaceId, label: workspace.label, ...details };
}

function matchingWindows(snapshot, desiredWindow) {
  return snapshot.windows.map((window) => ({ window, result: selectorResult(window, desiredWindow) }));
}

function workspaceIsActive(snapshot, workspace) {
  const activation = workspace.activation || (workspace.runner === 'office_document' ? { type: 'windowPresent', role: 'primary' } : { type: 'always' });
  if (activation.type === 'always') return true;
  if (activation.type !== 'windowPresent') return false;
  const watched = workspace.windows.find((window) => window.role === activation.role);
  return Boolean(watched && matchingWindows(snapshot, watched).some(({ result }) => result.matches));
}

function finalWindowOwners(workspaces, contextualApps = []) {
  const owners = new Map();
  for (const workspace of [...workspaces].reverse()) {
    for (const desiredWindow of workspace.windows) {
      if ((desiredWindow.ownership || 'lastApplicable') === 'independent') continue;
      if (!owners.has(desiredWindow.appKey)) owners.set(desiredWindow.appKey, workspace.workspaceId);
    }
  }
  for (const rule of contextualApps) {
    if (workspaces.some((workspace) => workspace.workspaceId === rule.ownerWorkspaceId)) owners.set(rule.appKey, rule.ownerWorkspaceId);
  }
  return owners;
}

function windowOccupiesSpace(window, knownGhostApps = []) {
  if (window.sticky) return false;
  const emptyNonmovableShell = !window.title && !window.role && !window.subrole && !window.movable;
  if (emptyNonmovableShell && knownGhostApps.includes(window.app)) return false;
  // Some applications leave an invisible root surface behind after their last
  // interactive window closes.  Requiring every negative signal keeps this
  // generic rule narrower than the reviewed per-application compatibility list.
  const headlessRootSurface = emptyNonmovableShell
    && !window.resizable
    && !window.visible
    && !window.hasAxReference;
  return !headlessRootSurface;
}

function emptyCleanupSpaces(snapshot, desired, bindings) {
  const occupants = snapshot.windows.filter((window) => windowOccupiesSpace(window, desired.nonoccupyingGhostApps || []));
  const ordinaryCount = (space) => occupants.filter((window) => window.space === space.index).length;
  const primaryDisplay = snapshot.displays.find((display) => display.uuid === bindings.primary);
  const home = primaryDisplay
    ? snapshot.spaces.filter((space) => space.display === primaryDisplay.index && !space.label).sort((a, b) => a.index - b.index)[0]
    : null;
  const candidates = [];
  for (const display of snapshot.displays) {
    const lane = snapshot.spaces.filter((space) => space.display === display.index).sort((a, b) => a.index - b.index);
    const survivor = lane.find((space) => home && space.uuid === home.uuid)
      || lane.find((space) => ordinaryCount(space) > 0)
      || lane[0];
    for (const space of lane) {
      if (!space.uuid || space.uuid === survivor?.uuid || ordinaryCount(space) > 0) continue;
      if (space.label && !/^sandbox_(solo|wide|tall)$/.test(space.label)) continue;
      candidates.push(space);
    }
  }
  return candidates.sort((a, b) => b.index - a.index);
}

function inferUnlabeledSpace(snapshot, workspace, expectedDisplay, owners, reservedSpaceUuids) {
  if (!expectedDisplay) return null;
  const candidateIndexes = new Set();
  for (const desiredWindow of workspace.windows) {
    if ((desiredWindow.ownership || 'lastApplicable') !== 'independent' && owners.get(desiredWindow.appKey) !== workspace.workspaceId) continue;
    for (const { window, result } of matchingWindows(snapshot, desiredWindow)) {
      if (result.matches) candidateIndexes.add(window.space);
    }
  }
  const candidates = snapshot.spaces.filter((space) => candidateIndexes.has(space.index)
    && space.display === expectedDisplay.index
    && !space.label
    && !reservedSpaceUuids.has(space.uuid));
  return candidates.length === 1 ? candidates[0] : null;
}

export function compareState(snapshot, desired, machine = {}) {
  const drifts = [];
  const matches = [];
  const bindings = machine.displayBindings || {};
  const usedWindowIds = new Set();
  if (snapshot.unavailable) drifts.push({ code: 'snapshot_unavailable', severity: 'blocker', message: snapshot.message || 'live state is unavailable' });
  const activeWorkspaces = desired.workspaces.filter((workspace) => {
    const active = workspaceIsActive(snapshot, workspace);
    if (!active) drifts.push(drift('workspace_inactive', 'warning', workspace, { reason: 'primary_window_missing' }));
    return active;
  });
  const owners = finalWindowOwners(activeWorkspaces, desired.contextualApps || []);
  const reservedSpaceUuids = new Set();
  const resolvedSpaces = new Map();
  for (const workspace of activeWorkspaces) {
    const expectedUuid = bindings[workspace.displayRole] || null;
    const expectedDisplay = expectedUuid ? snapshot.displays.find((display) => display.uuid === expectedUuid) : null;
    if (!expectedUuid) drifts.push(drift('display_binding_missing', 'blocker', workspace, { displayRole: workspace.displayRole }));
    else if (!expectedDisplay) drifts.push(drift('display_disconnected', 'blocker', workspace, { displayRole: workspace.displayRole, displayUuid: expectedUuid }));
    const labeledSpaces = snapshot.spaces.filter((space) => space.label === workspace.label);
    if (labeledSpaces.length > 1) drifts.push(drift('space_label_duplicate', 'blocker', workspace, { spaces: labeledSpaces.map((space) => space.uuid) }));
    let targetSpace = labeledSpaces[0] || null;
    if (!targetSpace) {
      targetSpace = inferUnlabeledSpace(snapshot, workspace, expectedDisplay, owners, reservedSpaceUuids);
      if (targetSpace) drifts.push(drift('space_label_missing', 'change', workspace, { displayRole: workspace.displayRole, spaceUuid: targetSpace.uuid, spaceIndex: targetSpace.index }));
      else drifts.push(drift('space_missing', 'change', workspace, { displayRole: workspace.displayRole }));
    }
    if (targetSpace) {
      reservedSpaceUuids.add(targetSpace.uuid);
      resolvedSpaces.set(workspace.workspaceId, targetSpace);
    }
    if (targetSpace && expectedDisplay && targetSpace.display !== expectedDisplay.index) drifts.push(drift('space_on_wrong_display', 'change', workspace, { spaceUuid: targetSpace.uuid, actualDisplay: targetSpace.display, expectedDisplay: expectedDisplay.index }));
    for (const desiredWindow of workspace.windows) {
      const candidates = matchingWindows(snapshot, desiredWindow);
      const ownership = desiredWindow.ownership || 'lastApplicable';
      const cardinality = desiredWindow.cardinality || (workspace.runner === 'gtd_support' && desiredWindow.role === 'dia' ? 'many' : 'one');
      const owner = ownership === 'independent' ? workspace.workspaceId : owners.get(desiredWindow.appKey);
      if (owner !== workspace.workspaceId) {
        matches.push({
          workspaceId: workspace.workspaceId,
          role: desiredWindow.role,
          required: desiredWindow.required,
          selectedWindowId: null,
          candidates: candidates.filter(({ result }) => result.matches).map(({ window }) => window.id),
          rejected: [],
          supersededByWorkspaceId: owner
        });
        continue;
      }
      const eligible = candidates.filter(({ window, result }) => result.matches && !usedWindowIds.has(window.id));
      const preferred = targetSpace ? eligible.filter(({ window }) => window.space === targetSpace.index) : [];
      const selected = cardinality === 'many'
        ? eligible.map(({ window }) => window)
        : [(preferred[0] || eligible[0])?.window].filter(Boolean);
      matches.push({
        workspaceId: workspace.workspaceId,
        role: desiredWindow.role,
        required: desiredWindow.required,
        selectedWindowId: selected[0]?.id || null,
        selectedWindowIds: selected.map((window) => window.id),
        candidates: candidates.filter(({ result }) => result.matches).map(({ window }) => window.id),
        rejected: candidates.filter(({ window, result }) => !result.matches && desiredWindow.appNames.includes(window.app)).map(({ window, result }) => ({ windowId: window.id, reasons: result.reasons }))
      });
      if (!selected.length) {
        drifts.push(drift(desiredWindow.required ? 'required_window_missing' : 'optional_window_missing', desiredWindow.required ? 'blocker' : 'warning', workspace, { role: desiredWindow.role, appKey: desiredWindow.appKey }));
        continue;
      }
      for (const window of selected) usedWindowIds.add(window.id);
      const ambiguous = cardinality === 'one' && eligible.length > 1 && preferred.length !== 1;
      if (ambiguous) drifts.push(drift('window_match_ambiguous', desiredWindow.required ? 'blocker' : 'warning', workspace, { role: desiredWindow.role, candidateWindowIds: eligible.map(({ window }) => window.id), selectedWindowId: selected[0].id }));
      for (const window of selected) {
        if (targetSpace && window.space !== targetSpace.index) drifts.push(drift('window_on_wrong_space', 'change', workspace, { role: desiredWindow.role, windowId: window.id, actualSpace: window.space, expectedSpaceUuid: targetSpace.uuid }));
      }
      const layout = workspace.layout.find((item) => item.role === desiredWindow.role);
      const geometry = cardinality === 'one' && selected.length === 1 ? geometryMatches(selected[0], expectedDisplay || snapshot.displays.find((display) => display.index === selected[0].display), layout) : null;
      if (!ambiguous && geometry?.comparable && !geometry.matches) drifts.push(drift('window_geometry_mismatch', 'change', workspace, { role: desiredWindow.role, windowId: selected[0].id, grid: layout.grid, geometry }));
    }
  }
  if (desired.orchestration?.focusWorkspace) {
    const focusSpace = resolvedSpaces.get(desired.orchestration.focusWorkspace);
    if (focusSpace && !focusSpace.focused) drifts.push({ code: 'workspace_focus_mismatch', severity: 'change', focusWorkspace: desired.orchestration.focusWorkspace, spaceUuid: focusSpace.uuid });
  }
  for (const space of emptyCleanupSpaces(snapshot, desired, bindings)) {
    drifts.push({
      code: 'empty_space_cleanup_required',
      severity: 'change',
      spaceUuid: space.uuid,
      spaceIndex: space.index,
      display: space.display,
      label: space.label
    });
  }
  if (desired.target.kind !== 'workspace') {
    for (const displayRole of new Set(activeWorkspaces.map((workspace) => workspace.displayRole))) {
      const expectedDisplay = snapshot.displays.find((display) => display.uuid === bindings[displayRole]);
      if (!expectedDisplay) continue;
      const lane = activeWorkspaces.filter((workspace) => workspace.displayRole === displayRole);
      const expected = lane.filter((workspace) => resolvedSpaces.has(workspace.workspaceId)).map((workspace) => workspace.workspaceId);
      const actual = lane.filter((workspace) => resolvedSpaces.has(workspace.workspaceId))
        .sort((a, b) => resolvedSpaces.get(a.workspaceId).index - resolvedSpaces.get(b.workspaceId).index)
        .map((workspace) => workspace.workspaceId);
      if (JSON.stringify(actual) !== JSON.stringify(expected)) drifts.push({ code: 'space_order_mismatch', severity: 'change', displayRole, expected, actual });
    }
  }
  const counts = drifts.reduce((result, item) => ({ ...result, [item.severity]: (result[item.severity] || 0) + 1 }), { blocker: 0, change: 0, warning: 0 });
  return {
    formatVersion: STATE_FORMAT_VERSION,
    snapshotId: snapshot.snapshotId,
    desiredStateId: desired.desiredStateId,
    target: clone(desired.target),
    converged: counts.blocker === 0 && counts.change === 0,
    counts,
    drifts,
    matches
  };
}

export function buildExecutionPlan(snapshot, desired, comparison, options = {}) {
  const orchestration = desired.orchestration || { displayProfile: null, focusWorkspace: null, reconcile: true };
  const actions = [];
  if (orchestration.displayProfile) actions.push({ type: 'apply_display_profile', profile: orchestration.displayProfile });
  for (const workspace of desired.workspaces) {
    const workspaceDrifts = comparison.drifts.filter((item) => item.workspaceId === workspace.workspaceId);
    if (workspaceDrifts.some((item) => item.code === 'space_missing')) actions.push({ type: 'ensure_space', workspaceId: workspace.workspaceId, label: workspace.label, displayRole: workspace.displayRole });
    for (const item of workspaceDrifts.filter((entry) => entry.code === 'space_label_missing')) actions.push({ type: 'recover_space_label', workspaceId: workspace.workspaceId, label: workspace.label, spaceUuid: item.spaceUuid, spaceIndex: item.spaceIndex });
    if (workspaceDrifts.some((item) => item.code === 'space_on_wrong_display')) actions.push({ type: 'move_space', workspaceId: workspace.workspaceId, label: workspace.label, displayRole: workspace.displayRole });
    for (const item of workspaceDrifts.filter((entry) => entry.code === 'window_on_wrong_space')) actions.push({ type: 'move_window', workspaceId: workspace.workspaceId, role: item.role, windowId: item.windowId, targetLabel: workspace.label });
    for (const item of workspaceDrifts.filter((entry) => entry.code === 'window_geometry_mismatch')) actions.push({ type: 'resize_window', workspaceId: workspace.workspaceId, role: item.role, windowId: item.windowId, grid: item.grid });
  }
  for (const item of comparison.drifts.filter((entry) => entry.code === 'empty_space_cleanup_required')) actions.push({ type: 'remove_empty_space', spaceUuid: item.spaceUuid, spaceIndex: item.spaceIndex, display: item.display, label: item.label });
  if (desired.target.kind !== 'workspace' && (actions.some((action) => ['ensure_space', 'recover_space_label', 'move_space'].includes(action.type)) || comparison.drifts.some((item) => item.code === 'space_order_mismatch'))) actions.push({ type: 'order_spaces', mode: desired.target.mode });
  const blockers = comparison.drifts.filter((item) => item.severity === 'blocker');
  const affectedWorkspaceIds = new Set(comparison.drifts.filter((item) => item.severity === 'change' && item.workspaceId).map((item) => item.workspaceId));
  const affectedWorkspaces = desired.workspaces.filter((workspace) => affectedWorkspaceIds.has(workspace.workspaceId));
  const needsFinalization = affectedWorkspaces.length > 0 || actions.some((action) => ['remove_empty_space', 'order_spaces'].includes(action.type));
  if (needsFinalization) actions.push({ type: 'finalize_mode', mode: desired.target.mode });
  if (orchestration.focusWorkspace && (actions.length || comparison.drifts.some((item) => item.code === 'workspace_focus_mismatch'))) actions.push({ type: 'focus_workspace', workspaceId: orchestration.focusWorkspace, mode: desired.target.mode });
  if (actions.length) actions.push({ type: 'verify', target: clone(desired.target) });
  const executionSteps = [];
  if (actions.some((action) => action.type === 'apply_display_profile')) executionSteps.push({ type: 'command', action: 'display_profile', command: ['display', orchestration.displayProfile] });
  if (affectedWorkspaces.length) {
    const includePostprocessors = desired.target.kind === 'mode';
    if (includePostprocessors) for (const hook of (desired.postprocessors || []).filter((item) => item.afterCommand == null)) executionSteps.push({ type: 'command', action: 'postprocess', command: ['postprocess', hook.name] });
    for (const workspace of desired.workspaces) {
      if (affectedWorkspaceIds.has(workspace.workspaceId)) executionSteps.push({ type: 'command', action: 'workspace', workspaceId: workspace.workspaceId, command: ['run', workspace.workspaceId, desired.target.mode] });
      if (includePostprocessors) for (const hook of (desired.postprocessors || []).filter((item) => item.afterCommand === workspace.runtimeId)) executionSteps.push({ type: 'command', action: 'postprocess', command: ['postprocess', hook.name] });
    }
  }
  if (needsFinalization) executionSteps.push({ type: 'command', action: 'finalize_mode', command: ['finalize', desired.target.mode] });
  if (actions.some((action) => action.type === 'focus_workspace')) executionSteps.push({ type: 'command', action: 'focus', command: ['focus', orchestration.focusWorkspace, desired.target.mode] });
  const planCore = {
    formatVersion: PLAN_FORMAT_VERSION,
    target: clone(desired.target),
    configDigest: desired.configDigest,
    runtimeSourceDigest: desired.runtimeSourceDigest,
    snapshotId: snapshot.snapshotId,
    desiredStateId: desired.desiredStateId,
    executable: blockers.length === 0,
    blockers,
    warnings: comparison.drifts.filter((item) => item.severity === 'warning'),
    actions,
    executionSteps,
    runnerCommands: executionSteps.map((step) => step.command),
    recovery: {
      snapshotId: snapshot.snapshotId,
      strategy: 'bounded_reconcile',
      automaticAttempts: options.automaticRecovery === false || orchestration.reconcile === false ? 0 : 1,
      windowIds: [...new Set(comparison.matches.flatMap((item) => item.selectedWindowIds || [item.selectedWindowId]).filter(Boolean))]
    }
  };
  return { ...planCore, planId: digest(planCore).slice(0, 20), createdAt: options.createdAt || new Date().toISOString() };
}

function slug(value) {
  const normalized = String(value || '').normalize('NFKD').toLowerCase().replace(/[^a-z0-9]+/g, '_').replace(/^_+|_+$/g, '');
  return /^[a-z]/.test(normalized) ? normalized : `app_${normalized || 'window'}`;
}

function captureGrid(windowFrame, displayFrame) {
  const actual = normalizedFrame(windowFrame, displayFrame);
  const clamp = (value, min, max) => Math.max(min, Math.min(max, value));
  const x = clamp(Math.round(actual.x * 12), 0, 11);
  const y = clamp(Math.round(actual.y * 12), 0, 11);
  const w = clamp(Math.round(actual.w * 12), 1, 12 - x);
  const h = clamp(Math.round(actual.h * 12), 1, 12 - y);
  return `12:12:${x}:${y}:${w}:${h}`;
}

export function captureWorkspace(snapshot, options = {}) {
  const mode = options.mode || 'wide';
  if (!MODES.has(mode)) throw new Error(`invalid capture mode “${mode}”; expected solo, wide, or tall`);
  const space = options.spaceUuid
    ? snapshot.spaces.find((item) => item.uuid === options.spaceUuid)
    : options.spaceIndex
      ? snapshot.spaces.find((item) => item.index === number(options.spaceIndex))
      : snapshot.spaces.find((item) => item.focused);
  if (!space) throw new Error('no Space selected; focus a Space or pass a valid Space UUID/index');
  const display = snapshot.displays.find((item) => item.index === space.display);
  if (!display) throw new Error(`display ${space.display} for the selected Space is unavailable`);
  const capturedWindows = snapshot.windows.filter((window) => window.space === space.index && !window.sticky && !window.nativeFullscreen && !window.minimized && window.hasAxReference);
  if (!capturedWindows.length) throw new Error('the selected Space has no visible non-sticky windows to capture');
  const apps = {};
  const windows = {};
  const regions = [];
  const appIds = new Map();
  for (const [index, window] of capturedWindows.entries()) {
    const base = slug(window.app);
    const appId = appIds.get(window.app) || base;
    appIds.set(window.app, appId);
    const role = index === 0 ? 'primary' : `window_${index + 1}`;
    apps[appId] ||= { name: window.app, match: { appNames: [window.app] } };
    windows[role] = { app: appId, required: index === 0, selector: { movable: window.movable, visible: true, ...(window.role ? { role: window.role } : {}), ...(window.subrole ? { subrole: window.subrole } : {}) } };
    regions.push({ role, grid: captureGrid(window.frame, display.frame) });
  }
  const workspaceId = options.workspaceId || slug(space.label || `captured_space_${space.index}`);
  const workspace = {
    name: options.name || (space.label ? space.label.split('_').map((part) => part[0]?.toUpperCase() + part.slice(1)).join(' ') : `Captured Space ${space.index}`),
    spaceLabel: options.spaceLabel || space.label || workspaceId,
    windows,
    variants: { [mode]: { layout: { type: 'canvas', regions } } }
  };
  return {
    formatVersion: STATE_FORMAT_VERSION,
    capturedFrom: { snapshotId: snapshot.snapshotId, spaceUuid: space.uuid, displayUuid: display.uuid, mode },
    draft: { workspaceId, workspace, apps },
    warnings: capturedWindows.filter((window) => !window.movable).map((window) => `window ${window.id} (${window.app}) is not movable and may require a dedicated adapter`)
  };
}

export function summarizeComparison(comparison) {
  return `${comparison.counts.blocker} blocker(s), ${comparison.counts.change} change(s), ${comparison.counts.warning} warning(s)`;
}
