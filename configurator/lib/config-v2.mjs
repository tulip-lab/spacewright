import { randomUUID } from 'node:crypto';

const MODES = ['solo', 'wide', 'tall'];
const DIRECTIONS = new Set(['rows', 'columns']);
const POSTPROCESSORS = new Set(['gtd_ai_expand_hermes_when_alone', 'workspace_reconcile_primary_fixed_spaces']);

export function starterConfig() {
  return {
    version: 2,
    metadata: { name: 'My SpaceWright setup' },
    apps: {
      code: { name: 'Visual Studio Code', match: { appNames: ['Code', 'Visual Studio Code'] } },
      chatgpt: { name: 'ChatGPT', match: { appNames: ['ChatGPT'] } }
    },
    displayRoles: {
      primary: { name: 'Primary display', portableMatch: { builtIn: true } },
      task: { name: 'Task display', portableMatch: { orientation: 'wide' } }
    },
    workspaces: {
      coding: {
        name: 'Coding',
        spaceLabel: 'coding',
        windows: {
          editor: { app: 'code', required: true, selector: { movable: true } },
          assistant: { app: 'chatgpt', required: false, selector: { movable: true } }
        },
        variants: {
          solo: { layout: { type: 'window', role: 'editor' } },
          wide: {
            layout: {
              type: 'split', direction: 'columns', weights: [1, 2],
              children: [{ type: 'window', role: 'assistant' }, { type: 'window', role: 'editor' }]
            }
          },
          tall: {
            layout: {
              type: 'split', direction: 'rows', weights: [1, 1],
              children: [{ type: 'window', role: 'assistant' }, { type: 'window', role: 'editor' }]
            }
          }
        }
      }
    },
    modes: {
      solo: { displays: [{ role: 'primary', workspaceOrder: ['coding'] }] },
      wide: { displays: [{ role: 'task', workspaceOrder: ['coding'] }] },
      tall: { displays: [{ role: 'task', workspaceOrder: ['coding'] }] }
    },
    shortcuts: [
      { id: randomUUID(), keys: { modifiers: ['alt', 'shift'], key: 'w' }, action: { type: 'activateMode', mode: 'wide' } },
      { id: randomUUID(), keys: { modifiers: ['alt', 'shift'], key: 't' }, action: { type: 'activateMode', mode: 'tall' } },
      { id: randomUUID(), keys: { modifiers: ['alt', 'shift'], key: 's' }, action: { type: 'activateMode', mode: 'solo' } }
    ]
  };
}

function object(value) {
  return value && typeof value === 'object' && !Array.isArray(value);
}

function id(value) {
  return typeof value === 'string' && /^[a-z][a-z0-9_]*$/.test(value);
}

function validateLayout(node, path, roles, errors, seen = new Set()) {
  if (!object(node)) return errors.push(`${path} must be an object`);
  if (seen.has(node)) return errors.push(`${path} contains a cycle`);
  seen.add(node);
  if (node.type === 'window') {
    if (!roles.has(node.role)) errors.push(`${path}.role references unknown window role "${node.role}"`);
  } else if (node.type === 'canvas') {
    if (!Array.isArray(node.regions) || !node.regions.length) errors.push(`${path}.regions must not be empty`);
    for (const [index, region] of (node.regions || []).entries()) {
      if (!roles.has(region.role)) errors.push(`${path}.regions[${index}].role references unknown window role "${region.role}"`);
      const hasGrid = typeof region.grid === 'string' && /^[0-9]+:[0-9]+:[0-9]+:[0-9]+:[0-9]+:[0-9]+$/.test(region.grid);
      const hasAbsolute = typeof region.move_abs === 'string' || typeof region.resize_abs === 'string';
      if (!hasGrid && !hasAbsolute) errors.push(`${path}.regions[${index}] must define grid or absolute geometry`);
    }
  } else if (node.type === 'split') {
    if (!DIRECTIONS.has(node.direction)) errors.push(`${path}.direction must be rows or columns`);
    if (!Array.isArray(node.children) || node.children.length < 2) errors.push(`${path}.children must contain at least two nodes`);
    if (!Array.isArray(node.weights) || node.weights.length !== node.children?.length || node.weights.some((n) => !Number.isInteger(n) || n < 1)) {
      errors.push(`${path}.weights must contain one positive integer per child`);
    }
    node.children?.forEach((child, index) => validateLayout(child, `${path}.children[${index}]`, roles, errors, seen));
  } else if (node.type !== 'empty') {
    errors.push(`${path}.type must be window, split, or empty`);
  }
  seen.delete(node);
}

export function validateV2(config) {
  const errors = [];
  if (!object(config) || config.version !== 2) return { valid: false, errors: ['version must be 2'] };
  for (const section of ['apps', 'displayRoles', 'workspaces', 'modes']) {
    if (!object(config[section])) errors.push(`${section} must be an object`);
  }
  if (errors.length) return { valid: false, errors };

  for (const [appId, app] of Object.entries(config.apps)) {
    if (!id(appId)) errors.push(`apps.${appId} has an invalid id`);
    if (!app?.name?.trim()) errors.push(`apps.${appId}.name is required`);
    if (!Array.isArray(app?.match?.appNames) || !app.match.appNames.length || app.match.appNames.some((name) => typeof name !== 'string' || !name.trim())) {
      errors.push(`apps.${appId}.match.appNames must contain at least one name`);
    }
  }
  for (const [roleId, role] of Object.entries(config.displayRoles)) {
    if (!id(roleId)) errors.push(`displayRoles.${roleId} has an invalid id`);
    if (!role?.name?.trim()) errors.push(`displayRoles.${roleId}.name is required`);
  }
  for (const [workspaceId, workspace] of Object.entries(config.workspaces)) {
    const path = `workspaces.${workspaceId}`;
    if (!id(workspaceId)) errors.push(`${path} has an invalid id`);
    if (!workspace?.name?.trim()) errors.push(`${path}.name is required`);
    if (!workspace?.spaceLabel?.trim()) errors.push(`${path}.spaceLabel is required`);
    if (!object(workspace?.windows) || !Object.keys(workspace.windows).length) errors.push(`${path}.windows must not be empty`);
    const roles = new Set(Object.keys(workspace?.windows || {}));
    for (const [role, window] of Object.entries(workspace?.windows || {})) {
      if (!id(role)) errors.push(`${path}.windows.${role} has an invalid id`);
      if (!config.apps[window.app]) errors.push(`${path}.windows.${role}.app references unknown app "${window.app}"`);
      if (typeof window.required !== 'boolean') errors.push(`${path}.windows.${role}.required must be boolean`);
    }
    if (!object(workspace?.variants)) errors.push(`${path}.variants must be an object`);
    for (const [mode, variant] of Object.entries(workspace?.variants || {})) {
      if (!MODES.includes(mode)) errors.push(`${path}.variants.${mode} is not a supported mode`);
      validateLayout(variant.layout, `${path}.variants.${mode}.layout`, roles, errors);
      if (variant.runtime?.windows) {
        if (!Array.isArray(variant.runtime.windows) || !variant.runtime.windows.length) errors.push(`${path}.variants.${mode}.runtime.windows must not be empty`);
        for (const [index, window] of (variant.runtime.windows || []).entries()) {
          if (!id(window.role)) errors.push(`${path}.variants.${mode}.runtime.windows[${index}].role is invalid`);
          if (!config.apps[window.app_key]) errors.push(`${path}.variants.${mode}.runtime.windows[${index}].app_key references an unknown app`);
          if (typeof window.required !== 'boolean') errors.push(`${path}.variants.${mode}.runtime.windows[${index}].required must be boolean`);
        }
      }
    }
  }
  for (const mode of MODES) {
    const definition = config.modes[mode];
    if (!definition) continue;
    if (!Array.isArray(definition.displays) || !definition.displays.length) errors.push(`modes.${mode}.displays must not be empty`);
    const placed = new Set();
    for (const [index, display] of (definition.displays || []).entries()) {
      if (!config.displayRoles[display.role]) errors.push(`modes.${mode}.displays[${index}].role references unknown display role "${display.role}"`);
      if (!Array.isArray(display.workspaceOrder)) errors.push(`modes.${mode}.displays[${index}].workspaceOrder must be an array`);
      for (const workspaceId of display.workspaceOrder || []) {
        const workspace = config.workspaces[workspaceId];
        if (!workspace) errors.push(`modes.${mode} references unknown workspace "${workspaceId}"`);
        else if (!workspace.variants?.[mode]) errors.push(`workspace "${workspaceId}" has no ${mode} variant`);
        if (placed.has(workspaceId)) errors.push(`workspace "${workspaceId}" appears twice in ${mode}`);
        placed.add(workspaceId);
      }
    }
    if (definition.cleanup && (!Array.isArray(definition.cleanup) || definition.cleanup.some((item) => typeof item !== 'string' || !/^[a-z_]+:(solo|wide|tall)$/.test(item)))) errors.push(`modes.${mode}.cleanup is invalid`);
    for (const [index, hook] of (definition.postprocessors || []).entries()) {
      if (!POSTPROCESSORS.has(hook.name)) errors.push(`modes.${mode}.postprocessors[${index}] is unsupported`);
      if (hook.afterCommand != null && typeof hook.afterCommand !== 'string') errors.push(`modes.${mode}.postprocessors[${index}].afterCommand must be a string or null`);
    }
  }
  const chords = new Set();
  for (const [index, shortcut] of (config.shortcuts || []).entries()) {
    const modifiers = [...(shortcut.keys?.modifiers || [])].sort();
    const key = shortcut.keys?.key;
    if (!key || modifiers.some((item) => !['cmd', 'ctrl', 'alt', 'shift', 'fn'].includes(item))) errors.push(`shortcuts[${index}] has invalid keys`);
    const chord = `${modifiers.join('+')}+${key}`;
    if (chords.has(chord)) errors.push(`shortcut chord ${chord} is duplicated`);
    chords.add(chord);
    if (shortcut.action?.type === 'activateMode' && !MODES.includes(shortcut.action.mode)) errors.push(`shortcuts[${index}] references an invalid mode`);
    else if (shortcut.action?.type === 'activateWorkspace') {
      if (!config.workspaces[shortcut.action.workspace]) errors.push(`shortcuts[${index}] references an unknown workspace`);
      if (!MODES.includes(shortcut.action.mode)) errors.push(`shortcuts[${index}] references an invalid workspace mode`);
      else if (config.workspaces[shortcut.action.workspace] && !config.workspaces[shortcut.action.workspace].variants?.[shortcut.action.mode]) errors.push(`shortcuts[${index}] references a missing workspace variant`);
    } else if (shortcut.action?.type !== 'activateMode') errors.push(`shortcuts[${index}] has an unsupported action`);
  }
  return { valid: errors.length === 0, errors };
}

function compileLayout(node, rect = { x: 0, y: 0, w: 120, h: 120 }, actions = []) {
  if (node.type === 'window') {
    actions.push({ role: node.role, grid: `120:120:${rect.x}:${rect.y}:${rect.w}:${rect.h}` });
    return actions;
  }
  if (node.type === 'empty') return actions;
  if (node.type === 'canvas') return node.regions.map((region) => ({ ...region }));
  const total = node.weights.reduce((sum, weight) => sum + weight, 0);
  let cursor = node.direction === 'columns' ? rect.x : rect.y;
  node.children.forEach((child, index) => {
    const full = node.direction === 'columns' ? rect.w : rect.h;
    const end = index === node.children.length - 1
      ? (node.direction === 'columns' ? rect.x + rect.w : rect.y + rect.h)
      : cursor + Math.round((full * node.weights[index]) / total);
    const childRect = node.direction === 'columns'
      ? { x: cursor, y: rect.y, w: end - cursor, h: rect.h }
      : { x: rect.x, y: cursor, w: rect.w, h: end - cursor };
    compileLayout(child, childRect, actions);
    cursor = end;
  });
  return actions;
}

export function compileV2(config) {
  const validation = validateV2(config);
  if (!validation.valid) throw new Error(validation.errors.join('\n'));
  const runtime = { version: 1, source_version: 2, apps: {}, display_roles: {}, layouts: {}, workspaces: {}, modes: {} };
  for (const [appId, app] of Object.entries(config.apps)) runtime.apps[appId] = { names: app.match.appNames };
  for (const mode of MODES) {
    for (const display of config.modes[mode]?.displays || []) {
      const runtimeRole = display.role === 'primary' ? 'primary' : `${display.role}__${mode}`;
      runtime.display_roles[runtimeRole] = {
        base_role: display.role,
        expected_mode: mode,
        portable_match: config.displayRoles[display.role].portableMatch || {}
      };
    }
  }
  for (const mode of MODES) {
    const steps = [];
    const hooks = config.modes[mode]?.postprocessors || [];
    for (const hook of hooks.filter((item) => item.afterCommand == null)) steps.push({ postprocessor: hook.name });
    for (const display of config.modes[mode]?.displays || []) {
      for (const workspaceId of display.workspaceOrder) {
        const workspace = config.workspaces[workspaceId];
        const variant = workspace.variants[mode];
        const runtimeId = variant.command || `spacewright_${workspaceId}_${mode}`;
        runtime.layouts[runtimeId] = compileLayout(variant.layout);
        runtime.workspaces[runtimeId] = {
          runner: variant.runtime?.runner || 'generic_layout',
          ...(variant.runtime?.runnerOptions ? { runner_options: variant.runtime.runnerOptions } : {}),
          label: variant.spaceLabel || `${workspace.spaceLabel}_${mode}`,
          display_role: variant.runtime?.displayRole || (display.role === 'primary' ? 'primary' : `${display.role}__${mode}`),
          space_layout: 'float',
          windows: variant.runtime?.windows || Object.entries(workspace.windows).map(([role, window]) => ({
            role, app_key: window.app, required: window.required, ...(window.selector ? { selector: window.selector } : {})
          })),
          layout_ref: runtimeId,
          ...(variant.runtime?.primaryAloneLayout ? { primary_alone_layout_ref: `${runtimeId}__primary_alone` } : {}),
          ...(variant.runtime?.cleanup ? { cleanup: variant.runtime.cleanup } : {}),
          ui: { workspace_id: workspaceId, name: workspace.name, mode, display_role: display.role }
        };
        if (variant.runtime?.primaryAloneLayout) runtime.layouts[`${runtimeId}__primary_alone`] = variant.runtime.primaryAloneLayout;
        steps.push({ workspace: runtimeId });
        for (const hook of hooks.filter((item) => item.afterCommand === runtimeId)) steps.push({ postprocessor: hook.name });
      }
    }
    runtime.modes[`work_${mode}`] = { display_mode: mode, steps, cleanup: config.modes[mode]?.cleanup || [] };
  }
  return runtime;
}

function modeSequence(v1, modeId, seen = new Set()) {
  if (seen.has(modeId)) throw new Error(`mode cycle detected at ${modeId}`);
  seen.add(modeId);
  const result = [];
  for (const step of v1.modes?.[modeId]?.steps || []) {
    if (step.workspace) result.push({ workspace: step.workspace });
    else if (step.mode) result.push(...modeSequence(v1, step.mode, seen));
    else if (step.postprocessor) result.push({ postprocessor: step.postprocessor });
  }
  seen.delete(modeId);
  return result;
}

export function migrateV1(v1) {
  if (!object(v1) || v1.version !== 1) throw new Error('migration input must be a v1 configuration');
  const v2 = { version: 2, metadata: { name: 'Migrated SpaceWright setup' }, apps: {}, displayRoles: {}, workspaces: {}, modes: {}, shortcuts: [] };
  for (const [appId, app] of Object.entries(v1.apps || {})) v2.apps[appId] = { name: app.names?.[0] || appId, match: { appNames: app.names || [appId] } };
  v2.displayRoles.primary = { name: 'Primary display', portableMatch: { builtIn: true } };
  v2.displayRoles.task = { name: 'Task display', portableMatch: {} };

  const commandMap = {};
  for (const [workspaceCommand, source] of Object.entries(v1.workspaces || {})) {
    const match = workspaceCommand.match(/^(.*)_(solo|wide|tall)$/);
    const baseId = match?.[1] || workspaceCommand;
    const declaredMode = match?.[2];
    const target = v2.workspaces[baseId] ||= { name: baseId.split('_').map((word) => word[0].toUpperCase() + word.slice(1)).join(' '), spaceLabel: baseId, windows: {}, variants: {} };
    for (const window of source.windows || []) {
      const prior = target.windows[window.role];
      const role = prior && prior.app !== window.app_key ? `${window.role}_${workspaceCommand}` : window.role;
      target.windows[role] = { app: window.app_key, required: window.required, ...(window.selector ? { selector: window.selector } : {}) };
    }
    commandMap[workspaceCommand] = { baseId, declaredMode, source };
  }

  for (const mode of MODES) {
    const sequence = modeSequence(v1, `work_${mode}`);
    const ordered = sequence.flatMap((step) => step.workspace ? [step.workspace] : []);
    const lanes = new Map();
    for (const command of ordered) {
      const entry = commandMap[command];
      if (!entry) continue;
      const role = ['primary', 'solo'].includes(entry.source.display_role) ? 'primary' : 'task';
      if (!lanes.has(role)) lanes.set(role, []);
      if (!lanes.get(role).includes(entry.baseId)) lanes.get(role).push(entry.baseId);
      const target = v2.workspaces[entry.baseId];
      const layout = v1.layouts?.[entry.source.layout_ref] || [];
      target.variants[mode] = {
        command,
        spaceLabel: entry.source.label,
        layout: { type: 'canvas', regions: layout.map((action) => ({ ...action })) },
        runtime: {
          runner: entry.source.runner,
          displayRole: entry.source.display_role,
          windows: entry.source.windows.map((window) => ({ ...window })),
          ...(entry.source.runner_options ? { runnerOptions: entry.source.runner_options } : {}),
          ...(entry.source.cleanup ? { cleanup: entry.source.cleanup } : {}),
          ...(entry.source.primary_alone_layout_ref ? { primaryAloneLayout: v1.layouts[entry.source.primary_alone_layout_ref] } : {})
        }
      };
    }
    let previousCommand = null;
    const postprocessors = [];
    for (const step of sequence) {
      if (step.workspace) previousCommand = step.workspace;
      else if (step.postprocessor) postprocessors.push({ name: step.postprocessor, afterCommand: previousCommand });
    }
    v2.modes[mode] = {
      displays: lanes.size ? [...lanes].map(([role, workspaceOrder]) => ({ role, workspaceOrder })) : [{ role: 'primary', workspaceOrder: [] }],
      cleanup: v1.modes?.[`work_${mode}`]?.cleanup || [],
      ...(postprocessors.length ? { postprocessors } : {})
    };
  }
  return v2;
}

const SKHD_MODIFIERS = { cmd: 'cmd', ctrl: 'ctrl', alt: 'alt', shift: 'shift', fn: 'fn' };

export function compileSkhd(config) {
  const validation = validateV2(config);
  if (!validation.valid) throw new Error(validation.errors.join('\n'));
  const lines = ['# Generated by SpaceWright. Do not edit this file directly.'];
  for (const shortcut of config.shortcuts || []) {
    const chord = shortcut.keys.modifiers.map((item) => SKHD_MODIFIERS[item]).join(' + ');
    const command = shortcut.action.type === 'activateMode'
      ? `work_${shortcut.action.mode}`
      : `spacewright run ${shortcut.action.workspace} ${shortcut.action.mode}`;
    lines.push(`${chord}${chord ? ' - ' : ''}${shortcut.keys.key} : fish -lc '${command}'`);
  }
  return `${lines.join('\n')}\n`;
}
