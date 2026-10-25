import { sameWindowIdentity } from './recovery.mjs';

// Tiny, unselected, non-resizable AX helper dialogs can be recreated as their parent
// moves (for example Electron's tiny "Window" surface). Keep them in discovery
// and occupancy checks, but not the immutable layout object census.
export function isObservationOverlay(window) {
  // These two accessory windows belong to the desktop test controller. Ordinary
  // system dialogs (including permission prompts) must still invalidate a plan.
  return window.app === 'ChatGPT'
    && (!window.bundleId || ['com.openai.codex', 'com.openai.chat'].includes(window.bundleId))
    && ['Computer Use', 'Computer Use Controls'].includes(window.title)
    && window.role === 'AXWindow' && window.subrole === 'AXSystemDialog'
    && window.hasAxReference && window.frameVerified && !window.resizable
    && !window.nativeFullscreen && window.frame.w > 0 && window.frame.w <= 600
    && window.frame.h > 0 && window.frame.h <= 400;
}
// AXHelpTag is a transient hover hint, not an application layout window. Require
// a verified, small, non-resizable surface; ordinary dialogs remain guarded.
export function isTransientTooltip(window) {
  return window.role === 'AXHelpTag' && !window.subrole
    && window.hasAxReference && window.frameVerified && !window.resizable
    && !window.nativeFullscreen && window.frame.w > 0 && window.frame.w <= 600
    && window.frame.h > 0 && window.frame.h <= 200;
}
export function executionCensus(windows,selected=[]) {
  const ids=new Set(selected.map(w=>typeof w==='number'?w:w.id));
  return windows.filter(w=>ids.has(w.id) || !w.ignoredDisplay && !isObservationOverlay(w) && !isTransientTooltip(w) && (w.role==='AXHelpTag' || w.resizable || w.subrole!=='AXDialog'
    || !w.frameVerified || !(w.frame.w>0 && w.frame.w<=100 && w.frame.h>0 && w.frame.h<=40)));
}

// Use the same object census at controller and executor boundaries. An ID alone
// is not an incarnation: apps can close a window and reuse its number.
export function assertWindowCensus(expected, windows, selected = []) {
  const current = executionCensus(windows, selected);
  const added = current.filter(w => !expected.some(saved => saved.id === w.id));
  const removed = expected.filter(saved => !current.some(w => w.id === saved.id));
  const changed = expected.filter(saved => {
    const live = current.find(w => w.id === saved.id);
    return live && !sameWindowIdentity(saved, live);
  });
  const duplicates = current.filter((w,index) => current.findIndex(candidate=>candidate.id===w.id)!==index);
  if (expected.length !== current.length || duplicates.length || added.length || removed.length || changed.length) {
    const changes = Object.fromEntries(Object.entries({added,removed,changed,duplicates})
      .map(([key,value]) => [key,value.map(({id,app})=>({id,app}))]));
    throw Object.assign(new Error(`global object census changed; replan required: ${JSON.stringify(changes)}`), {censusChanges:changes});
  }
  return current;
}

export function selectorResult(window, desired) {
  const selector = desired.selector || {};
  const reasons = [];
  // Ignored displays are excluded as destinations, never as window sources.
  if (isObservationOverlay(window) && desired.windowId !== window.id && selector.subrole !== 'AXSystemDialog') reasons.push('observation_overlay');
  if (isTransientTooltip(window) && desired.windowId !== window.id && selector.role !== 'AXHelpTag') reasons.push('transient_tooltip');
  if (desired.windowId != null && window.id !== desired.windowId) reasons.push('fixed_window');
  if (desired.appNames.length && !desired.appNames.includes(window.app)) reasons.push('app_name');
  // Standard yabai snapshots do not expose a bundle identifier. Treat bundle IDs
  // as a stronger match only when discovery supplied one, while retaining the
  // portable app-name fallback used by the Fish runtime.
  if (desired.bundleIds?.length && window.bundleId && !desired.bundleIds.includes(window.bundleId)) reasons.push('bundle_id');
  if (window.minimized) reasons.push('minimized');
  if (window.nativeFullscreen && !desired.allowNativeFullscreen) reasons.push('native_fullscreen_requires_adapter');
  if (selector.movable === true && !window.movable) reasons.push('not_movable');
  if (selector.resizable === true && !window.resizable) reasons.push('not_resizable');
  if (selector.visible === true && !window.visible) reasons.push('not_visible');
  if (selector.non_empty_title === true && !window.title) reasons.push('empty_title');
  if (selector.title_include && !window.title.includes(selector.title_include)) reasons.push('title_missing_required_text');
  if (selector.title_exclude && window.title.includes(selector.title_exclude)) reasons.push('title_contains_excluded_text');
  if (selector.role && window.role !== selector.role) reasons.push('role');
  if (selector.subrole && window.subrole !== selector.subrole) reasons.push('subrole');
  return { matches: reasons.length === 0, reasons };
}

export function selectRole(windows, desired, { used = [], targetSpace = null } = {}) {
  const usedIds = new Set(used);
  const eligible = windows.filter((w) => selectorResult(w, desired).matches && !usedIds.has(w.id)).sort((a,b) => a.id-b.id);
  const preferred = eligible.filter((w) => w.space === targetSpace);
  const ambiguous = (desired.cardinality || 'one') === 'one' && eligible.length > 1 && preferred.length !== 1;
  return { eligible, preferred, ambiguous, selected: ambiguous ? [] : desired.cardinality === 'many' ? eligible : [preferred[0] || eligible[0]].filter(Boolean) };
}

export function workspaceIsActive(snapshot, workspace) {
  const activation = workspace.activation || (workspace.runner === 'office_document' ? { type: 'windowPresent', role: 'primary' } : { type: 'always' });
  if (activation.type === 'always') return true;
  if (activation.type === 'anyWindowPresent') return workspace.windows.some(role=>snapshot.windows.some(window=>selectorResult(window,role).matches));
  if (activation.type !== 'windowPresent') return false;
  const watched = workspace.windows.find((window) => window.role === activation.role);
  return Boolean(watched && snapshot.windows.some(window=>selectorResult(window,watched).matches));
}

export function finalWindowOwners(workspaces, contextualApps = []) {
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
