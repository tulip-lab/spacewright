// Tiny, unselected, non-resizable AX helper dialogs can be recreated as their parent
// moves (for example Electron's tiny "Window" surface). Keep them in discovery
// and occupancy checks, but not the immutable layout object census.
export function executionCensus(windows,selected=[]) {
  const ids=new Set(selected.map(w=>typeof w==='number'?w:w.id));
  return windows.filter(w=>ids.has(w.id) || w.resizable || w.subrole!=='AXDialog'
    || !w.frameVerified || !(w.frame.w>0 && w.frame.w<=100 && w.frame.h>0 && w.frame.h<=40));
}

export function selectorResult(window, desired) {
  const selector = desired.selector || {};
  const reasons = [];
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
