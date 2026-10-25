import { readFileSync } from 'node:fs';
import { compileV2, validateJsonSchema, validateV2 } from './config-v2.mjs';

const V3_SCHEMA = JSON.parse(readFileSync(new URL('../../schemas/spacewright-v3.schema.json', import.meta.url), 'utf8'));

const object = (value) => Boolean(value) && typeof value === 'object' && !Array.isArray(value);
const idPattern = /^[a-z][a-z0-9_]*$/;
const FAMILIES = new Set(['macbook', 'mac_mini', 'other']);
const MODES = new Set(['solo', 'wide', 'tall']);
const KINDS = new Set(['built_in', 'external', 'sidecar']);
const ORIENTATIONS = new Set(['wide', 'tall', 'square']);
const clone = (value) => structuredClone(value);

function rejectUnknown(value, allowed, path, errors) {
  if (!object(value)) return;
  for (const key of Object.keys(value)) if (!allowed.has(key)) errors.push(`${path}.${key} is not supported`);
}

export function hardwareFamilyFromModel(model = '', productName = '') {
  const candidates = [model, productName].map((value) => String(value).trim().toLowerCase().replace(/[\s_-]+/g, ''));
  if (candidates.some((value) => value.startsWith('macbook'))) return 'macbook';
  if (candidates.some((value) => value.startsWith('macmini'))) return 'mac_mini';
  return 'other';
}

export function displayOrientation(display = {}) {
  const width = Number(display.frame?.w || display.width || 0);
  const height = Number(display.frame?.h || display.height || 0);
  if (!width || !height || width === height) return 'square';
  return width > height ? 'wide' : 'tall';
}

export function describeDisplays(snapshot = {}, machine = {}, { includeIgnored = false } = {}) {
  const kinds = machine.displayKinds || {};
  const roleByUuid = new Map(Object.entries(machine.displayBindings || {}).map(([role, uuid]) => [uuid, role]));
  return (snapshot.displays || []).filter(display => includeIgnored || kinds[display.uuid] !== 'ignored').map((display) => ({
    uuid: String(display.uuid || ''),
    role: roleByUuid.get(display.uuid) || display.role || null,
    kind: display.builtIn || display['is-built-in'] ? 'built_in' : kinds[display.uuid] === 'sidecar' ? 'sidecar' : 'external',
    ...(kinds[display.uuid] === 'ignored' ? { ignored: true } : {}),
    orientation: displayOrientation(display),
    frame: clone(display.frame || {}),
    index: Number(display.index || 0)
  })).sort((a, b) => a.index - b.index);
}

export function topologyKey(displays = []) {
  return displays.filter(display => !display.ignored).map((display) => `${display.kind}:${display.orientation}`).sort().join('+') || 'none';
}

function displayMatches(actual, expected, bindings = {}) {
  // One physical display may have different roles in different setups. A
  // confirmed binding is authoritative over describeDisplays' display label.
  const boundToRole = actual.uuid && bindings[expected.role] === actual.uuid;
  if (expected.role && actual.role && actual.role !== expected.role && !boundToRole) return false;
  if (expected.kind && actual.kind !== expected.kind) return false;
  if (expected.orientation && actual.orientation !== expected.orientation) return false;
  return true;
}

function matchDisplaySet(actual, expected, allowAdditionalDisplays, bindings = {}) {
  if (!allowAdditionalDisplays && actual.length !== expected.length) return false;
  if (actual.length < expected.length) return false;
  const used = new Set();
  const assign = (index) => {
    if (index === expected.length) return true;
    for (let candidate = 0; candidate < actual.length; candidate += 1) {
      if (used.has(candidate) || !displayMatches(actual[candidate], expected[index], bindings)) continue;
      used.add(candidate);
      if (assign(index + 1)) return true;
      used.delete(candidate);
    }
    return false;
  };
  return assign(0);
}

// Confirmations describe concrete sets; match conditions may omit kind/direction.
// Current geometry is not the target geometry until the display profile runs.
export function resolveModeTransition(config, { machine = {}, hardware = {}, snapshot = {}, mode } = {}) {
  const selected = selectHardwareProfile(config, machine, hardware);
  if (!selected.id || !machine.hardwareProfileConfirmed) throw new Error('hardware profile requires confirmation before switching mode');
  if (snapshot.unavailable || snapshot.completeness && snapshot.completeness !== 'complete') throw new Error(snapshot.message || 'display discovery is incomplete');
  const physical = describeDisplays(snapshot, machine);
  const candidates = [];
  for (const [setupId, setup] of Object.entries(config.hardwareProfiles[selected.id].setups)) {
    if (setup.compatibilityMode !== mode) continue;
    const requirements = setup.match.displays;
    const roles = new Set([...requirements.map(d => d.role), ...setup.lanes.map(l => l.role)].filter(Boolean));
    const bound = new Set();
    const bindingsValid = [...roles].every(role => {
      const uuid = machine.displayBindings?.[role];
      const display = physical.find(d => d.uuid === uuid);
      if (!display || bound.has(uuid)) return false;
      bound.add(uuid);
      return requirements.filter(d => d.role === role).every(d => !d.kind || d.kind === display.kind);
    });
    if (!bindingsValid) continue;
    const withoutOrientation = displays => displays.map(({ orientation, ...display }) => display);
    if (!matchDisplaySet(physical, withoutOrientation(requirements), setup.match.allowAdditionalDisplays === true, machine.displayBindings)) continue;
    for (const [key, confirmedSetup] of Object.entries(machine.topologySelections || {})) {
      if (confirmedSetup !== setupId || !/^(built_in|external|sidecar):(wide|tall|square)(\+(built_in|external|sidecar):(wide|tall|square))*$/.test(key)) continue;
      const confirmed = key.split('+').map(part => { const [kind, orientation] = part.split(':'); return {kind, orientation}; });
      if (topologyKey(confirmed) !== key) continue;
      if (!matchDisplaySet(confirmed, requirements, setup.match.allowAdditionalDisplays === true)) continue;
      if (!matchDisplaySet(withoutOrientation(physical), withoutOrientation(confirmed), false)) continue;
      candidates.push({hardwareProfileId:selected.id, setupId, topologyKey:key, v2:projectSetupToV2(config, selected.id, setupId)});
    }
  }
  if (candidates.length !== 1) throw new Error(`target setup for ${mode} is ambiguous, unconfirmed or missing required physical bindings`);
  return candidates[0];
}

export function matchingSetups(config, hardwareProfileId, snapshot = {}, machine = {}) {
  const profile = config.hardwareProfiles?.[hardwareProfileId];
  if (!profile || snapshot.unavailable) return [];
  const actual = describeDisplays(snapshot, machine);
  return Object.entries(profile.setups || {}).filter(([, setup]) => (
    matchDisplaySet(actual, setup.match?.displays || [], setup.match?.allowAdditionalDisplays === true, machine.displayBindings)
  )).map(([id]) => id);
}

export function setupBindingStatus(config, hardwareProfileId, setupId, snapshot = {}, machine = {}) {
  const setup = config.hardwareProfiles?.[hardwareProfileId]?.setups?.[setupId];
  const requirements = setup?.match?.displays || [];
  const displays = describeDisplays(snapshot, machine);
  const missingRoles = [];
  const roles = new Set([...requirements.map(r => r.role), ...(setup?.lanes || []).map(l => l.role)].filter(Boolean));
  const used = new Set();
  for (const role of roles) {
    const uuid = machine.displayBindings?.[role];
    const display = uuid ? displays.find((candidate) => candidate.uuid === uuid) : null;
    if (!display || used.has(uuid) || !requirements.filter(r => r.role === role).every(r => displayMatches(display, r, machine.displayBindings))) missingRoles.push(role);
    if (display) used.add(uuid);
  }
  return { ready: missingRoles.length === 0, missingRoles };
}

export function selectHardwareProfile(config, machine = {}, hardware = {}) {
  if (machine.hardwareProfile && config.hardwareProfiles?.[machine.hardwareProfile]) {
    return { id: machine.hardwareProfile, source: machine.hardwareProfileConfirmed ? 'confirmed' : 'saved', candidates: [machine.hardwareProfile] };
  }
  const family = hardware.family || hardwareFamilyFromModel(hardware.modelIdentifier);
  const candidates = Object.entries(config.hardwareProfiles || {})
    .filter(([, profile]) => !profile.match?.family || profile.match.family === family)
    .map(([id]) => id);
  return { id: candidates.length === 1 ? candidates[0] : null, source: candidates.length === 1 ? 'detected' : 'ambiguous', candidates, family };
}

export function resolveV3(config, { machine = {}, hardware = {}, snapshot = {}, setupId = null, requireConfirmation = true } = {}) {
  const validation = validateV3(config);
  if (!validation.valid) throw new Error(validation.errors.join('\n'));
  if (snapshot.unavailable) throw new Error(snapshot.message || 'display discovery is unavailable');
  const selectedHardware = selectHardwareProfile(config, machine, hardware);
  if (!selectedHardware.id) throw new Error(`hardware profile is ${selectedHardware.candidates.length ? 'ambiguous' : 'unmatched'} for family “${selectedHardware.family || 'unknown'}”`);
  if (requireConfirmation && !machine.hardwareProfileConfirmed) throw new Error(`hardware profile “${selectedHardware.id}” requires confirmation`);
  const displays = describeDisplays(snapshot, machine);
  const key = topologyKey(displays);
  const candidates = matchingSetups(config, selectedHardware.id, snapshot, machine);
  const saved = setupId || machine.topologySelections?.[key] || machine.activeSetup;
  let selectedSetup = saved && candidates.includes(saved) ? saved : null;
  let source = selectedSetup ? (setupId ? 'requested' : machine.topologySelections?.[key] ? 'confirmed' : 'active') : 'detected';
  if (!selectedSetup && candidates.length === 1) selectedSetup = candidates[0];
  if (!selectedSetup) throw new Error(`display setup is ${candidates.length ? 'ambiguous' : 'unmatched'} for topology “${key}”`);
  if (requireConfirmation && machine.topologySelections?.[key] !== selectedSetup) throw new Error(`display setup “${selectedSetup}” for topology “${key}” requires confirmation`);
  const bindingStatus = setupBindingStatus(config, selectedHardware.id, selectedSetup, snapshot, machine);
  if (requireConfirmation && !bindingStatus.ready) throw new Error(`display setup “${selectedSetup}” requires renewed role binding: ${bindingStatus.missingRoles.join(', ')}`);
  return {
    hardwareProfileId: selectedHardware.id,
    setupId: selectedSetup,
    topologyKey: key,
    displays,
    candidates,
    bindingStatus,
    source,
    v2: projectSetupToV2(config, selectedHardware.id, selectedSetup)
  };
}

function configurationWindows(workspace, configuration) {
  if (!configuration.runtime?.windows) {
    return Object.entries(workspace.windows || {}).map(([role, window]) => ({
      role,
      app_key: window.app,
      required: window.required,
      ...(window.ownership ? { ownership: window.ownership } : {}),
      ...(window.cardinality ? { cardinality: window.cardinality } : {}),
      ...(window.selector ? { selector: clone(window.selector) } : {})
    }));
  }
  return configuration.runtime.windows.map((window) => {
    const sharedSelector = workspace.windows?.[window.role]?.selector || {};
    const selector = { ...clone(sharedSelector), ...clone(window.selector || {}) };
    return { ...clone(window), ...(Object.keys(selector).length ? { selector } : {}) };
  });
}

function layoutRoles(layout, roles = []) {
  if (!layout) return roles;
  if (layout.role) roles.push(layout.role);
  for (const child of layout.children || []) layoutRoles(child, roles);
  for (const region of layout.regions || []) if (region.role) roles.push(region.role);
  return roles;
}

export function projectSetupToV2(config, hardwareProfileId, setupId) {
  const profile = config.hardwareProfiles?.[hardwareProfileId];
  const setup = profile?.setups?.[setupId];
  if (!setup) throw new Error(`unknown display setup “${hardwareProfileId}.${setupId}”`);
  const mode = setup.compatibilityMode;
  const v2 = {
    version: 2,
    metadata: { name: `${config.metadata?.name || 'SpaceWright'} · ${profile.name} · ${setup.name}` },
    apps: clone(config.apps),
    ...(config.aiProviders ? { aiProviders: clone(config.aiProviders) } : {}),
    displayRoles: clone(config.displayRoles),
    workspaces: {},
    modes: {
      solo: { displays: [{ role: Object.keys(config.displayRoles)[0], workspaceOrder: [] }] },
      wide: { displays: [{ role: Object.keys(config.displayRoles)[0], workspaceOrder: [] }] },
      tall: { displays: [{ role: Object.keys(config.displayRoles)[0], workspaceOrder: [] }] }
    },
    ...(config.settings ? { settings: clone(config.settings) } : {}),
    shortcuts: []
  };
  v2.modes[mode] = {
    displays: clone(setup.lanes),
    ...(setup.cleanup ? { cleanup: clone(setup.cleanup) } : {}),
    ...(setup.contextualApps ? { contextualApps: clone(setup.contextualApps) } : {}),
    ...(setup.postprocessors ? { postprocessors: clone(setup.postprocessors) } : {})
  };
  for (const workspaceId of setup.lanes.flatMap((lane) => lane.workspaceOrder)) {
    const workspace = config.workspaces[workspaceId];
    const configurationId = setup.workspaceConfigurations[workspaceId] || workspace.defaultConfiguration;
    const configuration = workspace.configurations[configurationId];
    const runtimeId = configuration.command || `spacewright_${workspaceId}_${configurationId}`;
    const projectedRuntime = configuration.runtime ? { ...clone(configuration.runtime), windows: clone(configurationWindows(workspace, configuration)) } : null;
    // v3 lanes own placement. A migrated variant's old displayRole must not
    // disagree with the planner or split single-display ordering into two lanes.
    if (projectedRuntime) delete projectedRuntime.displayRole;
    v2.workspaces[workspaceId] = {
      name: workspace.name,
      spaceLabel: workspace.spaceLabel,
      windows: clone(workspace.windows),
      variants: {
        [mode]: {
          layout: clone(configuration.layout),
          command: runtimeId,
          spaceLabel: configuration.spaceLabel || `${workspace.spaceLabel}_${configurationId}`,
          ...(configuration.activation ? { activation: clone(configuration.activation) } : {}),
          ...(projectedRuntime ? { runtime: projectedRuntime } : {})
        }
      }
    };
  }
  if (config.aiRouting) {
    const assignments = {};
    for (const [workspaceId, assignment] of Object.entries(config.aiRouting.assignments || {})) {
      if (!v2.workspaces[workspaceId]) continue;
      const configurationId = setup.workspaceConfigurations[workspaceId] || config.workspaces[workspaceId].defaultConfiguration;
      assignments[workspaceId] = {
        role: assignment.configurationRoleOverrides?.[configurationId] || assignment.role,
        provider: assignment.configurationOverrides?.[configurationId] || assignment.provider
      };
    }
    if (Object.keys(assignments).length && v2.workspaces[config.aiRouting.fallbackWorkspace]) {
      v2.aiRouting = { assignments, fallbackWorkspace: config.aiRouting.fallbackWorkspace, focusOwner: config.aiRouting.focusOwner === true };
    }
  }
  for (const shortcut of config.shortcuts || []) {
    if (shortcut.action.type === 'activateWorkspace' && v2.workspaces[shortcut.action.workspace]) {
      v2.shortcuts.push({ ...clone(shortcut), action: { type: 'activateWorkspace', workspace: shortcut.action.workspace, mode } });
    } else if (shortcut.action.type === 'activateSetup' && shortcut.action.hardwareProfile === hardwareProfileId && shortcut.action.setup === setupId) {
      v2.shortcuts.push({ ...clone(shortcut), action: { type: 'activateMode', mode } });
    }
  }
  return v2;
}

export function validateV3(config) {
  const errors = validateJsonSchema(config, V3_SCHEMA);
  const warnings = [];
  if (!object(config) || config.version !== 3) return { valid: false, errors: [...errors, 'version must be 3'], warnings };
  if (errors.length) return { valid: false, errors, warnings };
  rejectUnknown(config, new Set(['version', 'metadata', 'apps', 'aiProviders', 'aiRouting', 'displayRoles', 'workspaces', 'hardwareProfiles', 'shortcuts', 'settings']), 'config', errors);
  rejectUnknown(config.settings, new Set(['executionBudgets', 'eventAutomationEnabled', 'cleanupEmptySpaces', 'tallTopPercent', 'topologyStableSamples', 'topologyCooldownSeconds']), 'settings', errors);
  for (const key of ['apps', 'displayRoles', 'workspaces', 'hardwareProfiles']) if (!object(config[key]) || !Object.keys(config[key]).length) errors.push(`${key} must be a non-empty object`);
  for (const [profileId, profile] of Object.entries(config.hardwareProfiles || {})) {
    const path = `hardwareProfiles.${profileId}`;
    if (!idPattern.test(profileId)) errors.push(`${path} has an invalid id`);
    rejectUnknown(profile, new Set(['name', 'match', 'setups']), path, errors);
    rejectUnknown(profile.match, new Set(['family']), `${path}.match`, errors);
    if (!profile.name?.trim()) errors.push(`${path}.name is required`);
    if (!FAMILIES.has(profile.match?.family)) errors.push(`${path}.match.family must be macbook, mac_mini, or other`);
    if (!object(profile.setups) || !Object.keys(profile.setups).length) errors.push(`${path}.setups must be a non-empty object`);
    for (const [setupId, setup] of Object.entries(profile.setups || {})) {
      const setupPath = `${path}.setups.${setupId}`;
      if (!idPattern.test(setupId)) errors.push(`${setupPath} has an invalid id`);
      rejectUnknown(setup, new Set(['name', 'compatibilityMode', 'match', 'lanes', 'workspaceConfigurations', 'displayConfig', 'focusWorkspace', 'cleanup', 'contextualApps', 'postprocessors']), setupPath, errors);
      rejectUnknown(setup.match, new Set(['displays', 'allowAdditionalDisplays']), `${setupPath}.match`, errors);
      if (!setup.name?.trim()) errors.push(`${setupPath}.name is required`);
      if (!MODES.has(setup.compatibilityMode)) errors.push(`${setupPath}.compatibilityMode must be solo, wide, or tall`);
      if (!Array.isArray(setup.match?.displays) || !setup.match.displays.length) errors.push(`${setupPath}.match.displays must be non-empty`);
      for (const [index, display] of (setup.match?.displays || []).entries()) {
        rejectUnknown(display, new Set(['role', 'kind', 'orientation']), `${setupPath}.match.displays[${index}]`, errors);
        if (display.kind && !KINDS.has(display.kind)) errors.push(`${setupPath}.match.displays[${index}].kind is invalid`);
        if (display.orientation && !ORIENTATIONS.has(display.orientation)) errors.push(`${setupPath}.match.displays[${index}].orientation is invalid`);
        if (display.role && !config.displayRoles?.[display.role]) errors.push(`${setupPath}.match.displays[${index}].role references an unknown display role`);
      }
      if (!Array.isArray(setup.lanes) || !setup.lanes.length) errors.push(`${setupPath}.lanes must be non-empty`);
      const placed = new Set();
      for (const [index, lane] of (setup.lanes || []).entries()) {
        rejectUnknown(lane, new Set(['role', 'workspaceOrder']), `${setupPath}.lanes[${index}]`, errors);
        if (!config.displayRoles?.[lane.role]) errors.push(`${setupPath}.lanes[${index}].role references an unknown display role`);
        if (!Array.isArray(lane.workspaceOrder)) errors.push(`${setupPath}.lanes[${index}].workspaceOrder must be an array`);
        for (const workspaceId of lane.workspaceOrder || []) {
          if (!config.workspaces?.[workspaceId]) errors.push(`${setupPath} references unknown workspace “${workspaceId}”`);
          if (placed.has(workspaceId)) errors.push(`${setupPath} places workspace “${workspaceId}” more than once`);
          placed.add(workspaceId);
        }
      }
      if (!object(setup.workspaceConfigurations)) errors.push(`${setupPath}.workspaceConfigurations must be an object`);
      for (const workspaceId of placed) {
        const workspace = config.workspaces?.[workspaceId];
        const configurationId = setup.workspaceConfigurations?.[workspaceId] || workspace?.defaultConfiguration;
        if (!configurationId) errors.push(`${setupPath}.workspaceConfigurations.${workspaceId} is required because the workspace has no defaultConfiguration`);
        else if (!workspace?.configurations?.[configurationId]) errors.push(`${setupPath}.workspaceConfigurations.${workspaceId} references unknown configuration “${configurationId}”`);
      }
      for (const workspaceId of Object.keys(setup.workspaceConfigurations || {})) if (!placed.has(workspaceId)) warnings.push(`${setupPath}.workspaceConfigurations.${workspaceId} is unused because the workspace is not placed`);
    }
  }
  for (const [workspaceId, workspace] of Object.entries(config.workspaces || {})) {
    const path = `workspaces.${workspaceId}`;
    if (!idPattern.test(workspaceId)) errors.push(`${path} has an invalid id`);
    rejectUnknown(workspace, new Set(['name', 'spaceLabel', 'windows', 'defaultConfiguration', 'configurations']), path, errors);
    if (!workspace.name?.trim()) errors.push(`${path}.name is required`);
    if (!workspace.spaceLabel?.trim()) errors.push(`${path}.spaceLabel is required`);
    if (!object(workspace.windows) || !Object.keys(workspace.windows).length) errors.push(`${path}.windows must be non-empty`);
    if (!object(workspace.configurations) || !Object.keys(workspace.configurations).length) errors.push(`${path}.configurations must be non-empty`);
    if (workspace.defaultConfiguration && !workspace.configurations?.[workspace.defaultConfiguration]) errors.push(`${path}.defaultConfiguration references an unknown configuration`);
    for (const [role, window] of Object.entries(workspace.windows || {})) {
      if (!config.apps?.[window.app]) errors.push(`${path}.windows.${role}.app references unknown app “${window.app}”`);
    }
    for (const [configurationId, configuration] of Object.entries(workspace.configurations || {})) {
      if (!idPattern.test(configurationId)) errors.push(`${path}.configurations.${configurationId} has an invalid id`);
      rejectUnknown(configuration, new Set(['layout', 'command', 'spaceLabel', 'activation', 'runtime']), `${path}.configurations.${configurationId}`, errors);
      if (!object(configuration.layout)) errors.push(`${path}.configurations.${configurationId}.layout is required`);
      const roles = layoutRoles(configuration.layout);
      for (const role of roles) if (!workspace.windows?.[role]) errors.push(`${path}.configurations.${configurationId}.layout references unknown window role “${role}”`);
      for (const [role, window] of Object.entries(workspace.windows || {})) if (window.required && !roles.includes(role)) errors.push(`${path}.configurations.${configurationId}.layout does not place required window role “${role}”`);
    }
  }
  for (const [index, shortcut] of (config.shortcuts || []).entries()) {
    if (shortcut.action.type === 'activateWorkspace' && !config.workspaces?.[shortcut.action.workspace]) errors.push(`shortcuts[${index}] references unknown workspace “${shortcut.action.workspace}”`);
    if (shortcut.action.type === 'activateSetup' && !config.hardwareProfiles?.[shortcut.action.hardwareProfile]?.setups?.[shortcut.action.setup]) errors.push(`shortcuts[${index}] references unknown setup “${shortcut.action.hardwareProfile}.${shortcut.action.setup}”`);
  }
  const projectionErrors = [];
  if (!errors.length) {
    for (const [profileId, profile] of Object.entries(config.hardwareProfiles)) {
      for (const setupId of Object.keys(profile.setups)) {
        try {
          const projected = projectSetupToV2(config, profileId, setupId);
          const result = validateV2(projected);
          for (const error of result.errors) projectionErrors.push(`${profileId}.${setupId}: ${error}`);
          for (const warning of result.warnings) warnings.push(`${profileId}.${setupId}: ${warning}`);
        } catch (error) { projectionErrors.push(`${profileId}.${setupId}: ${error.message}`); }
      }
    }
  }
  errors.push(...projectionErrors);
  return { valid: errors.length === 0, errors, warnings };
}

export function compileV3(config, resolution) {
  const resolved = resolution?.v2 ? resolution : resolveV3(config, resolution);
  const runtime = compileV2(resolved.v2);
  for (const [modeId, mode] of Object.entries(runtime.modes)) if (!mode.steps.length) delete runtime.modes[modeId];
  runtime.source_version = 3;
  runtime.active_hardware_profile = resolved.hardwareProfileId;
  runtime.active_setup = resolved.setupId;
  runtime.topology_key = resolved.topologyKey;
  const setup = config.hardwareProfiles[resolved.hardwareProfileId].setups[resolved.setupId];
  runtime.workspace_configurations = Object.fromEntries(setup.lanes.flatMap((lane) => lane.workspaceOrder).map((workspaceId) => [
    workspaceId,
    setup.workspaceConfigurations[workspaceId] || config.workspaces[workspaceId].defaultConfiguration
  ]));
  return runtime;
}

export function compileSkhdV3(config, resolution) {
  const resolved = resolution?.v2 ? resolution : resolveV3(config, resolution);
  const lines = ['# Generated by SpaceWright. Do not edit this file directly.'];
  for (const shortcut of config.shortcuts || []) {
    let command = null;
    if (shortcut.action.type === 'activateWorkspace' && resolved.v2.workspaces[shortcut.action.workspace]) {
      command = `spacewright workspace ${shortcut.action.workspace}`;
    } else if (shortcut.action.type === 'activateSetup'
      && shortcut.action.hardwareProfile === resolved.hardwareProfileId
      && shortcut.action.setup === resolved.setupId) {
      command = 'spacewright setup activate';
    }
    if (!command) continue;
    const chord = shortcut.keys.modifiers.join(' + ');
    lines.push(`${chord}${chord ? ' - ' : ''}${shortcut.keys.key} : fish -lc '${command}'`);
  }
  return `${lines.join('\n')}\n`;
}

export function migrateV2ToV3(v2) {
  const validation = validateV2(v2);
  if (!validation.valid) throw new Error(validation.errors.join('\n'));
  const v3 = {
    version: 3,
    metadata: clone(v2.metadata || { name: 'Migrated SpaceWright setup' }),
    apps: clone(v2.apps),
    ...(v2.aiProviders ? { aiProviders: clone(v2.aiProviders) } : {}),
    displayRoles: clone(v2.displayRoles),
    workspaces: {},
    hardwareProfiles: {
      macbook: { name: 'MacBook', match: { family: 'macbook' }, setups: {} },
      mac_mini: { name: 'Mac mini', match: { family: 'mac_mini' }, setups: {} },
      other: { name: 'Other Mac', match: { family: 'other' }, setups: {} }
    },
    shortcuts: (v2.shortcuts || []).filter((shortcut) => shortcut.action.type === 'activateWorkspace').map((shortcut) => ({ ...clone(shortcut), action: { type: 'activateWorkspace', workspace: shortcut.action.workspace } })),
    ...(v2.settings ? { settings: clone(v2.settings) } : {})
  };
  for (const [workspaceId, workspace] of Object.entries(v2.workspaces)) {
    v3.workspaces[workspaceId] = { name: workspace.name, spaceLabel: workspace.spaceLabel, windows: clone(workspace.windows), configurations: {} };
    for (const [mode, variant] of Object.entries(workspace.variants || {})) v3.workspaces[workspaceId].configurations[mode] = clone(variant);
    if (workspace.variants.solo) v3.workspaces[workspaceId].defaultConfiguration = 'solo';
    else v3.workspaces[workspaceId].defaultConfiguration = Object.keys(workspace.variants)[0];
  }
  const setupSpecs = {
    solo: { displays: [{ kind: 'built_in' }], compatibilityMode: 'solo' },
    wide: { displays: [{ kind: 'built_in' }, { kind: 'external', orientation: 'wide' }], compatibilityMode: 'wide' },
    tall: { displays: [{ kind: 'built_in' }, { kind: 'external', orientation: 'tall' }], compatibilityMode: 'tall' }
  };
  const allWorkspaceOrder = [...new Set([
    ...['solo', 'wide', 'tall'].flatMap((mode) => (v2.modes[mode]?.displays || []).flatMap((lane) => lane.workspaceOrder)),
    ...Object.keys(v2.workspaces)
  ])];
  const completeLanes = (mode) => {
    const lanes = clone(v2.modes[mode]?.displays || []);
    const placed = new Set(lanes.flatMap((lane) => lane.workspaceOrder));
    for (const workspaceId of allWorkspaceOrder) {
      if (placed.has(workspaceId)) continue;
      const preferredRole = v2.workspaces[workspaceId]?.variants?.[mode]?.runtime?.displayRole;
      const lane = lanes.find((candidate) => candidate.role === preferredRole) || lanes[0];
      if (!lane) continue;
      lane.workspaceOrder.push(workspaceId);
      placed.add(workspaceId);
    }
    return lanes;
  };
  const placement = (mode) => {
    const lanes = completeLanes(mode);
    const order = lanes.flatMap((lane) => lane.workspaceOrder);
    return { lanes, order, workspaceConfigurations: Object.fromEntries(order.map((workspaceId) => [workspaceId, mode])) };
  };
  for (const [mode, modeConfig] of Object.entries(v2.modes)) {
    const modePlacement = placement(mode);
    const base = {
      name: mode[0].toUpperCase() + mode.slice(1),
      compatibilityMode: setupSpecs[mode].compatibilityMode,
      match: { displays: clone(setupSpecs[mode].displays) },
      lanes: modePlacement.lanes,
      workspaceConfigurations: modePlacement.workspaceConfigurations,
      ...(modeConfig.cleanup ? { cleanup: clone(modeConfig.cleanup) } : {}),
      ...(modeConfig.contextualApps ? { contextualApps: clone(modeConfig.contextualApps) } : {}),
      ...(modeConfig.postprocessors ? { postprocessors: clone(modeConfig.postprocessors) } : {})
    };
    v3.hardwareProfiles.macbook.setups[mode] = base;
  }
  const firstRole = Object.keys(v2.displayRoles)[0];
  const secondaryRole = Object.keys(v2.displayRoles).find((role) => role !== firstRole) || firstRole;
  if (!v3.displayRoles.sidecar) v3.displayRoles.sidecar = { name: 'Sidecar', portableMatch: {} };
  for (const mode of ['solo', 'wide', 'tall']) {
    const base = v3.hardwareProfiles.macbook.setups[mode];
    if (!base) continue;
    const setupId = mode === 'solo' ? 'built_in_sidecar' : `built_in_${mode}_sidecar`;
    v3.hardwareProfiles.macbook.setups[setupId] = {
      ...clone(base),
      name: `${base.name} + Sidecar`,
      match: { displays: [...clone(base.match.displays), { role: 'sidecar', kind: 'sidecar' }] },
      lanes: [...clone(base.lanes), ...base.lanes.some((lane) => lane.role === 'sidecar') ? [] : [{ role: 'sidecar', workspaceOrder: [] }]]
    };
  }
  const widePlacement = placement('wide');
  const tallPlacement = placement('tall');
  const soloPlacement = placement('solo');
  const wideRole = widePlacement.lanes[0]?.role || secondaryRole;
  const tallRole = tallPlacement.lanes[0]?.role || firstRole;
  const singleTallConfiguration = 'mac_mini_single_tall';
  const singleTallWorkspaceConfigurations = {};
  for (const workspaceId of tallPlacement.order) {
    const base = v3.workspaces[workspaceId].configurations.tall;
    if (!base) continue;
    v3.workspaces[workspaceId].configurations[singleTallConfiguration] = {
      ...clone(base),
      runtime: { runner: base.runtime?.runner || 'generic_layout', ...clone(base.runtime || {}), displayRole: tallRole }
    };
    singleTallWorkspaceConfigurations[workspaceId] = singleTallConfiguration;
  }
  v3.hardwareProfiles.mac_mini.setups.single_wide = { name: 'Single wide', compatibilityMode: 'wide', match: { displays: [{ kind: 'external', orientation: 'wide' }] }, lanes: [{ role: wideRole, workspaceOrder: widePlacement.order }], workspaceConfigurations: widePlacement.workspaceConfigurations };
  v3.hardwareProfiles.mac_mini.setups.single_tall = { name: 'Single tall', compatibilityMode: 'tall', match: { displays: [{ kind: 'external', orientation: 'tall' }] }, lanes: [{ role: tallRole, workspaceOrder: tallPlacement.order }], workspaceConfigurations: singleTallWorkspaceConfigurations };
  v3.hardwareProfiles.mac_mini.setups.wide_tall = { name: 'Wide + tall', compatibilityMode: 'wide', match: { displays: [{ kind: 'external', orientation: 'wide' }, { kind: 'external', orientation: 'tall' }] }, lanes: [{ role: secondaryRole, workspaceOrder: widePlacement.order }, { role: firstRole, workspaceOrder: [] }], workspaceConfigurations: widePlacement.workspaceConfigurations };
  v3.hardwareProfiles.mac_mini.setups.wide_sidecar = { name: 'Wide + Sidecar', compatibilityMode: 'wide', match: { displays: [{ kind: 'external', orientation: 'wide' }, { kind: 'sidecar' }] }, lanes: [{ role: wideRole, workspaceOrder: widePlacement.order }, { role: 'sidecar', workspaceOrder: [] }], workspaceConfigurations: widePlacement.workspaceConfigurations };
  v3.hardwareProfiles.mac_mini.setups.tall_sidecar = { name: 'Tall + Sidecar', compatibilityMode: 'tall', match: { displays: [{ kind: 'external', orientation: 'tall' }, { kind: 'sidecar' }] }, lanes: [{ role: tallRole, workspaceOrder: tallPlacement.order }, { role: 'sidecar', workspaceOrder: [] }], workspaceConfigurations: tallPlacement.workspaceConfigurations };
  v3.hardwareProfiles.other.setups.default = { name: 'Default', compatibilityMode: 'solo', match: { displays: [{ kind: 'external' }], allowAdditionalDisplays: true }, lanes: [{ role: firstRole, workspaceOrder: soloPlacement.order }], workspaceConfigurations: soloPlacement.workspaceConfigurations };
  if (v2.aiRouting) {
    v3.aiRouting = {
      assignments: Object.fromEntries(Object.entries(v2.aiRouting.assignments || {}).map(([workspaceId, assignment]) => [workspaceId, {
        role: assignment.role,
        provider: assignment.provider,
        ...(assignment.overrides ? { configurationOverrides: clone(assignment.overrides) } : {}),
        ...(assignment.roleOverrides ? { configurationRoleOverrides: clone(assignment.roleOverrides) } : {})
      }])),
      fallbackWorkspace: v2.aiRouting.fallbackWorkspace,
      focusOwner: v2.aiRouting.focusOwner === true
    };
  }
  return v3;
}

export function starterV3() {
  return {
    version: 3,
    metadata: { name: 'SpaceWright hardware-aware setup' },
    apps: { code: { name: 'Visual Studio Code', match: { appNames: ['Code', 'Visual Studio Code'] } } },
    displayRoles: {
      built_in: { name: 'Built-in display', portableMatch: { builtIn: true } },
      wide: { name: 'Wide display', portableMatch: { orientation: 'wide' } },
      tall: { name: 'Tall display', portableMatch: { orientation: 'tall' } },
      sidecar: { name: 'Sidecar', portableMatch: {} }
    },
    workspaces: {
      coding: {
        name: 'Coding', spaceLabel: 'coding', defaultConfiguration: 'laptop',
        windows: { editor: { app: 'code', required: true, selector: { movable: true } } },
        configurations: {
          laptop: { layout: { type: 'window', role: 'editor' } },
          wide: { layout: { type: 'window', role: 'editor' } },
          tall: { layout: { type: 'window', role: 'editor' } }
        }
      }
    },
    hardwareProfiles: {
      macbook: {
        name: 'MacBook', match: { family: 'macbook' }, setups: {
          built_in: { name: 'Built-in display', compatibilityMode: 'solo', match: { displays: [{ role: 'built_in', kind: 'built_in' }] }, lanes: [{ role: 'built_in', workspaceOrder: ['coding'] }], workspaceConfigurations: { coding: 'laptop' } },
          built_in_wide: { name: 'Built-in + wide', compatibilityMode: 'wide', match: { displays: [{ role: 'built_in', kind: 'built_in' }, { role: 'wide', kind: 'external', orientation: 'wide' }] }, lanes: [{ role: 'wide', workspaceOrder: ['coding'] }], workspaceConfigurations: { coding: 'wide' } },
          built_in_tall: { name: 'Built-in + tall', compatibilityMode: 'tall', match: { displays: [{ role: 'built_in', kind: 'built_in' }, { role: 'tall', kind: 'external', orientation: 'tall' }] }, lanes: [{ role: 'tall', workspaceOrder: ['coding'] }], workspaceConfigurations: { coding: 'tall' } },
          built_in_sidecar: { name: 'Built-in + Sidecar', compatibilityMode: 'solo', match: { displays: [{ role: 'built_in', kind: 'built_in' }, { role: 'sidecar', kind: 'sidecar' }] }, lanes: [{ role: 'built_in', workspaceOrder: ['coding'] }, { role: 'sidecar', workspaceOrder: [] }], workspaceConfigurations: { coding: 'laptop' } },
          built_in_wide_sidecar: { name: 'Built-in + wide + Sidecar', compatibilityMode: 'wide', match: { displays: [{ role: 'built_in', kind: 'built_in' }, { role: 'wide', kind: 'external', orientation: 'wide' }, { role: 'sidecar', kind: 'sidecar' }] }, lanes: [{ role: 'wide', workspaceOrder: ['coding'] }, { role: 'sidecar', workspaceOrder: [] }], workspaceConfigurations: { coding: 'wide' } },
          built_in_tall_sidecar: { name: 'Built-in + tall + Sidecar', compatibilityMode: 'tall', match: { displays: [{ role: 'built_in', kind: 'built_in' }, { role: 'tall', kind: 'external', orientation: 'tall' }, { role: 'sidecar', kind: 'sidecar' }] }, lanes: [{ role: 'tall', workspaceOrder: ['coding'] }, { role: 'sidecar', workspaceOrder: [] }], workspaceConfigurations: { coding: 'tall' } }
        }
      },
      mac_mini: {
        name: 'Mac mini', match: { family: 'mac_mini' }, setups: {
          single_wide: { name: 'Single wide', compatibilityMode: 'wide', match: { displays: [{ role: 'wide', kind: 'external', orientation: 'wide' }] }, lanes: [{ role: 'wide', workspaceOrder: ['coding'] }], workspaceConfigurations: { coding: 'wide' } },
          single_tall: { name: 'Single tall', compatibilityMode: 'tall', match: { displays: [{ role: 'tall', kind: 'external', orientation: 'tall' }] }, lanes: [{ role: 'tall', workspaceOrder: ['coding'] }], workspaceConfigurations: { coding: 'tall' } },
          wide_tall: { name: 'Wide + tall', compatibilityMode: 'wide', match: { displays: [{ role: 'wide', kind: 'external', orientation: 'wide' }, { role: 'tall', kind: 'external', orientation: 'tall' }] }, lanes: [{ role: 'wide', workspaceOrder: ['coding'] }, { role: 'tall', workspaceOrder: [] }], workspaceConfigurations: { coding: 'wide' } },
          wide_sidecar: { name: 'Wide + Sidecar', compatibilityMode: 'wide', match: { displays: [{ role: 'wide', kind: 'external', orientation: 'wide' }, { role: 'sidecar', kind: 'sidecar' }] }, lanes: [{ role: 'wide', workspaceOrder: ['coding'] }, { role: 'sidecar', workspaceOrder: [] }], workspaceConfigurations: { coding: 'wide' } },
          tall_sidecar: { name: 'Tall + Sidecar', compatibilityMode: 'tall', match: { displays: [{ role: 'tall', kind: 'external', orientation: 'tall' }, { role: 'sidecar', kind: 'sidecar' }] }, lanes: [{ role: 'tall', workspaceOrder: ['coding'] }, { role: 'sidecar', workspaceOrder: [] }], workspaceConfigurations: { coding: 'tall' } }
        }
      },
      other: {
        name: 'Other Mac', match: { family: 'other' }, setups: {
          default: { name: 'Default display', compatibilityMode: 'solo', match: { displays: [{ kind: 'external' }], allowAdditionalDisplays: true }, lanes: [{ role: 'wide', workspaceOrder: ['coding'] }], workspaceConfigurations: { coding: 'laptop' } }
        }
      }
    },
    shortcuts: []
  };
}
