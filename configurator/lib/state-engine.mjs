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

export function buildDesiredState(config, runtime, target = {}) {
  const resolved = targetDefinition(config, target);
  const placement = new Map();
  for (const display of config.modes[resolved.mode].displays) for (const workspaceId of display.workspaceOrder) placement.set(workspaceId, display.role);
  const workspaces = resolved.workspaceIds.map((workspaceId) => {
    const workspace = config.workspaces[workspaceId];
    const variant = workspace.variants[resolved.mode];
    const runtimeId = variant.command || `spacewright_${workspaceId}_${resolved.mode}`;
    const configuredWindows = variant.runtime?.windows || Object.entries(workspace.windows).map(([role, window]) => ({
      role, app_key: window.app, required: window.required, ...(window.selector ? { selector: window.selector } : {})
    }));
    return {
      runtimeId,
      workspaceId,
      name: workspace.name,
      mode: resolved.mode,
      label: variant.spaceLabel || `${workspace.spaceLabel}_${resolved.mode}`,
      displayRole: placement.get(workspaceId),
      runtimeDisplayRole: variant.runtime?.displayRole || placement.get(workspaceId),
      layout: compileLayout(variant.layout),
      windows: configuredWindows.map((window) => ({
        role: window.role,
        appKey: window.app_key,
        appNames: clone(config.apps?.[window.app_key]?.match?.appNames || []),
        bundleIds: clone(config.apps?.[window.app_key]?.match?.bundleIds || []),
        required: Boolean(window.required),
        selector: clone(window.selector || {})
      }))
    };
  });
  const desired = {
    formatVersion: STATE_FORMAT_VERSION,
    target: { kind: resolved.kind, id: resolved.id, mode: resolved.mode },
    workspaces,
    cleanup: clone(runtime.modes?.[`work_${resolved.mode}`]?.cleanup || []),
    orchestration: resolved.profile ? {
      displayProfile: resolved.profile.displayConfig?.profile || null,
      focusWorkspace: resolved.profile.focusBehaviour?.workspace || null,
      reconcile: resolved.profile.settings?.reconcile !== false
    } : { displayProfile: null, focusWorkspace: null, reconcile: true },
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

export function compareState(snapshot, desired, machine = {}) {
  const drifts = [];
  const matches = [];
  const bindings = machine.displayBindings || {};
  const usedWindowIds = new Set();
  if (snapshot.unavailable) drifts.push({ code: 'snapshot_unavailable', severity: 'blocker', message: snapshot.message || 'live state is unavailable' });
  for (const workspace of desired.workspaces) {
    const expectedUuid = bindings[workspace.displayRole] || null;
    const expectedDisplay = expectedUuid ? snapshot.displays.find((display) => display.uuid === expectedUuid) : null;
    if (!expectedUuid) drifts.push(drift('display_binding_missing', 'blocker', workspace, { displayRole: workspace.displayRole }));
    else if (!expectedDisplay) drifts.push(drift('display_disconnected', 'blocker', workspace, { displayRole: workspace.displayRole, displayUuid: expectedUuid }));
    const labeledSpaces = snapshot.spaces.filter((space) => space.label === workspace.label);
    if (!labeledSpaces.length) drifts.push(drift('space_missing', 'change', workspace, { displayRole: workspace.displayRole }));
    if (labeledSpaces.length > 1) drifts.push(drift('space_label_duplicate', 'blocker', workspace, { spaces: labeledSpaces.map((space) => space.uuid) }));
    const targetSpace = labeledSpaces[0] || null;
    if (targetSpace && expectedDisplay && targetSpace.display !== expectedDisplay.index) drifts.push(drift('space_on_wrong_display', 'change', workspace, { spaceUuid: targetSpace.uuid, actualDisplay: targetSpace.display, expectedDisplay: expectedDisplay.index }));
    for (const desiredWindow of workspace.windows) {
      const candidates = snapshot.windows.map((window) => ({ window, result: selectorResult(window, desiredWindow) }));
      const eligible = candidates.filter(({ window, result }) => result.matches && !usedWindowIds.has(window.id));
      const preferred = targetSpace ? eligible.filter(({ window }) => window.space === targetSpace.index) : [];
      const selected = (preferred[0] || eligible[0])?.window || null;
      matches.push({
        workspaceId: workspace.workspaceId,
        role: desiredWindow.role,
        required: desiredWindow.required,
        selectedWindowId: selected?.id || null,
        candidates: candidates.filter(({ result }) => result.matches).map(({ window }) => window.id),
        rejected: candidates.filter(({ window, result }) => !result.matches && desiredWindow.appNames.includes(window.app)).map(({ window, result }) => ({ windowId: window.id, reasons: result.reasons }))
      });
      if (!selected) {
        drifts.push(drift(desiredWindow.required ? 'required_window_missing' : 'optional_window_missing', desiredWindow.required ? 'blocker' : 'warning', workspace, { role: desiredWindow.role, appKey: desiredWindow.appKey }));
        continue;
      }
      usedWindowIds.add(selected.id);
      if (eligible.length > 1 && preferred.length !== 1) drifts.push(drift('window_match_ambiguous', desiredWindow.required ? 'blocker' : 'warning', workspace, { role: desiredWindow.role, candidateWindowIds: eligible.map(({ window }) => window.id), selectedWindowId: selected.id }));
      if (targetSpace && selected.space !== targetSpace.index) drifts.push(drift('window_on_wrong_space', 'change', workspace, { role: desiredWindow.role, windowId: selected.id, actualSpace: selected.space, expectedSpaceUuid: targetSpace.uuid }));
      const layout = workspace.layout.find((item) => item.role === desiredWindow.role);
      const geometry = geometryMatches(selected, expectedDisplay || snapshot.displays.find((display) => display.index === selected.display), layout);
      if (geometry.comparable && !geometry.matches) drifts.push(drift('window_geometry_mismatch', 'change', workspace, { role: desiredWindow.role, windowId: selected.id, grid: layout.grid, geometry }));
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
  const actions = [];
  for (const workspace of desired.workspaces) {
    const workspaceDrifts = comparison.drifts.filter((item) => item.workspaceId === workspace.workspaceId);
    if (workspaceDrifts.some((item) => item.code === 'space_missing')) actions.push({ type: 'ensure_space', workspaceId: workspace.workspaceId, label: workspace.label, displayRole: workspace.displayRole });
    if (workspaceDrifts.some((item) => item.code === 'space_on_wrong_display')) actions.push({ type: 'move_space', workspaceId: workspace.workspaceId, label: workspace.label, displayRole: workspace.displayRole });
    for (const item of workspaceDrifts.filter((entry) => entry.code === 'window_on_wrong_space')) actions.push({ type: 'move_window', workspaceId: workspace.workspaceId, role: item.role, windowId: item.windowId, targetLabel: workspace.label });
    for (const item of workspaceDrifts.filter((entry) => entry.code === 'window_geometry_mismatch')) actions.push({ type: 'resize_window', workspaceId: workspace.workspaceId, role: item.role, windowId: item.windowId, grid: item.grid });
  }
  if (desired.target.kind !== 'workspace') actions.push({ type: 'order_spaces', mode: desired.target.mode });
  if (actions.length) actions.push({ type: 'verify', target: clone(desired.target) });
  const blockers = comparison.drifts.filter((item) => item.severity === 'blocker');
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
    runnerCommands: [
      ...(desired.orchestration.displayProfile ? [['display', desired.orchestration.displayProfile]] : []),
      ...(desired.target.kind === 'workspace'
        ? [['run', desired.target.id, desired.target.mode]]
        : desired.target.kind === 'mode'
          ? [['run', `work_${desired.target.mode}`]]
          : desired.workspaces.map((workspace) => ['run', workspace.workspaceId, desired.target.mode])),
      ...(desired.orchestration.focusWorkspace ? [['focus', desired.orchestration.focusWorkspace, desired.target.mode]] : [])
    ],
    recovery: {
      snapshotId: snapshot.snapshotId,
      strategy: 'bounded_reconcile',
      automaticAttempts: options.automaticRecovery === false || desired.orchestration.reconcile === false ? 0 : 1,
      windowIds: comparison.matches.map((item) => item.selectedWindowId).filter(Boolean)
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
