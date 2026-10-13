export function matchingRules(config, context) {
  return (config.rules || []).filter((rule) => rule.enabled && Object.entries(rule.when || {}).every(([key, value]) => {
    if (key === 'app') return context.apps?.includes(value);
    return context[key] === value;
  }));
}

export function ruleContext(config, event, snapshot, topology) {
  const appNames = new Set(snapshot.windows.map((window) => window.app));
  const apps = Object.entries(config.apps || {}).filter(([, app]) => app.match.appNames.some((name) => appNames.has(name))).map(([id]) => id);
  const focusedSpace = snapshot.spaces.find((space) => space.focused);
  const workspace = focusedSpace ? Object.entries(config.workspaces || {}).find(([, definition]) => Object.entries(definition.variants || {}).some(([mode, variant]) => (variant.spaceLabel || `${definition.spaceLabel}_${mode}`) === focusedSpace.label))?.[0] || null : null;
  const display = snapshot.displays.find((item) => item.focused)?.role || null;
  return { event, topology, orientation: topology.startsWith('tall') ? 'tall' : topology.startsWith('wide') ? 'wide' : null, apps, workspace, display, layout: focusedSpace?.layout || null };
}

export function classifyTopology(displays) {
  const active = displays.filter((display) => display['is-visible'] !== false);
  if (!active.length) return 'unknown';
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
