import { randomUUID } from 'node:crypto';
import { readFileSync } from 'node:fs';

const MODES = ['solo', 'wide', 'tall'];
const DIRECTIONS = new Set(['rows', 'columns']);
const POSTPROCESSORS = new Set(['gtd_ai_expand_hermes_when_alone', 'workspace_reconcile_primary_fixed_spaces']);
const ROOT_KEYS = new Set(['version', 'metadata', 'apps', 'aiProviders', 'aiRouting', 'displayRoles', 'workspaces', 'modes', 'shortcuts', 'profiles', 'rules', 'settings']);
export const CONFIG_COMPILER_VERSION = 3;
const V2_SCHEMA = JSON.parse(readFileSync(new URL('../../schemas/spacewright-v2.schema.json', import.meta.url), 'utf8'));

function schemaTypeMatches(value, type) {
  if (type === 'object') return object(value);
  if (type === 'array') return Array.isArray(value);
  if (type === 'integer') return Number.isInteger(value);
  if (type === 'number') return typeof value === 'number' && Number.isFinite(value);
  if (type === 'null') return value === null;
  return typeof value === type;
}

function schemaValueKey(value) {
  return JSON.stringify(value, Object.keys(object(value) ? value : {}).sort());
}

function validateSchemaNode(value, schema, path, errors) {
  if (schema.$ref) {
    const target = schema.$ref.split('/').slice(1).reduce((node, token) => node[token.replaceAll('~1', '/').replaceAll('~0', '~')], V2_SCHEMA);
    return validateSchemaNode(value, target, path, errors);
  }
  if (schema.oneOf || schema.anyOf) {
    const branches = schema.oneOf || schema.anyOf;
    const matches = branches.filter((branch) => {
      const branchErrors = [];
      validateSchemaNode(value, branch, path, branchErrors);
      return branchErrors.length === 0;
    }).length;
    const valid = schema.oneOf ? matches === 1 : matches > 0;
    if (!valid) errors.push(`${path} does not match a supported shape`);
  }
  if (schema.const !== undefined && value !== schema.const) errors.push(`${path} must equal ${JSON.stringify(schema.const)}`);
  if (schema.enum && !schema.enum.includes(value)) errors.push(`${path} must be one of ${schema.enum.join(', ')}`);
  if (schema.type) {
    const types = Array.isArray(schema.type) ? schema.type : [schema.type];
    if (!types.some((type) => schemaTypeMatches(value, type))) {
      errors.push(`${path} must be ${types.join(' or ')}`);
      return;
    }
  }
  if (typeof value === 'string') {
    if (schema.minLength != null && value.length < schema.minLength) errors.push(`${path} must not be empty`);
    if (schema.pattern && !new RegExp(schema.pattern).test(value)) errors.push(`${path} has an invalid format`);
  }
  if (typeof value === 'number' && schema.minimum != null && value < schema.minimum) errors.push(`${path} must be at least ${schema.minimum}`);
  if (Array.isArray(value)) {
    if (schema.minItems != null && value.length < schema.minItems) errors.push(`${path} must contain at least ${schema.minItems} item(s)`);
    if (schema.uniqueItems && new Set(value.map(schemaValueKey)).size !== value.length) errors.push(`${path} must contain unique items`);
    if (schema.items) value.forEach((item, index) => validateSchemaNode(item, schema.items, `${path}[${index}]`, errors));
  }
  if (object(value)) {
    if (schema.minProperties != null && Object.keys(value).length < schema.minProperties) errors.push(`${path} must contain at least ${schema.minProperties} field(s)`);
    for (const required of schema.required || []) if (!(required in value)) errors.push(`${path}.${required} is required`);
    for (const [key, child] of Object.entries(value)) {
      if (schema.propertyNames) validateSchemaNode(key, schema.propertyNames, `${path}.${key}`, errors);
      if (schema.properties?.[key]) validateSchemaNode(child, schema.properties[key], `${path}.${key}`, errors);
      else if (object(schema.additionalProperties)) validateSchemaNode(child, schema.additionalProperties, `${path}.${key}`, errors);
      else if (schema.additionalProperties === false) errors.push(`${path}.${key} is not supported`);
    }
  }
}

export function validateV2Schema(config) {
  const errors = [];
  validateSchemaNode(config, V2_SCHEMA, '$', errors);
  return errors;
}

function rejectUnknown(value, allowed, path, errors) {
  if (!object(value)) return;
  for (const key of Object.keys(value)) if (!allowed.has(key)) errors.push(`${path}.${key} is not supported`);
}

export function starterConfig() {
  return {
    version: 2,
    metadata: { name: 'My SpaceWright setup' },
    apps: {
      code: { name: 'Visual Studio Code', match: { appNames: ['Code', 'Visual Studio Code'] } },
      chatgpt: { name: 'ChatGPT', match: { appNames: ['ChatGPT'] } }
    },
    aiProviders: {
      chatgpt: { name: 'ChatGPT', app: 'chatgpt' }
    },
    aiRouting: {
      assignments: {},
      fallbackWorkspace: 'coding',
      focusOwner: true
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

function validateLayout(node, path, roles, errors, usedRoles, seen = new Set()) {
  if (!object(node)) return errors.push(`${path} must be an object`);
  if (seen.has(node)) return errors.push(`${path} contains a cycle`);
  seen.add(node);
  if (node.type === 'window') {
    rejectUnknown(node, new Set(['type', 'role']), path, errors);
    if (!roles.has(node.role)) errors.push(`${path}.role references unknown window role "${node.role}"`);
    else if (usedRoles.has(node.role)) errors.push(`${path}.role places window role "${node.role}" more than once`);
    else usedRoles.add(node.role);
  } else if (node.type === 'canvas') {
    rejectUnknown(node, new Set(['type', 'regions']), path, errors);
    if (!Array.isArray(node.regions) || !node.regions.length) errors.push(`${path}.regions must not be empty`);
    for (const [index, region] of (node.regions || []).entries()) {
      if (!roles.has(region.role)) errors.push(`${path}.regions[${index}].role references unknown window role "${region.role}"`);
      else if (usedRoles.has(region.role)) errors.push(`${path}.regions[${index}].role places window role "${region.role}" more than once`);
      else usedRoles.add(region.role);
      rejectUnknown(region, new Set(['role', 'grid', 'move_abs', 'resize_abs']), `${path}.regions[${index}]`, errors);
      const hasGrid = typeof region.grid === 'string' && /^[0-9]+:[0-9]+:[0-9]+:[0-9]+:[0-9]+:[0-9]+$/.test(region.grid);
      const hasAbsolute = typeof region.move_abs === 'string' || typeof region.resize_abs === 'string';
      if (!hasGrid && !hasAbsolute) errors.push(`${path}.regions[${index}] must define grid or absolute geometry`);
    }
  } else if (node.type === 'split') {
    rejectUnknown(node, new Set(['type', 'direction', 'weights', 'children']), path, errors);
    if (!DIRECTIONS.has(node.direction)) errors.push(`${path}.direction must be rows or columns`);
    if (!Array.isArray(node.children) || node.children.length < 2) errors.push(`${path}.children must contain at least two nodes`);
    if (!Array.isArray(node.weights) || node.weights.length !== node.children?.length || node.weights.some((n) => !Number.isInteger(n) || n < 1)) {
      errors.push(`${path}.weights must contain one positive integer per child`);
    }
    node.children?.forEach((child, index) => validateLayout(child, `${path}.children[${index}]`, roles, errors, usedRoles, seen));
  } else if (node.type !== 'empty') {
    errors.push(`${path}.type must be window, split, or empty`);
  } else {
    rejectUnknown(node, new Set(['type']), path, errors);
  }
  seen.delete(node);
}

export function validateV2(config) {
  const errors = validateV2Schema(config);
  const warnings = [];
  if (!object(config) || config.version !== 2) return { valid: false, errors: ['version must be 2'], warnings };
  rejectUnknown(config, ROOT_KEYS, '$', errors);
  rejectUnknown(config.metadata, new Set(['name']), 'metadata', errors);
  let invalidSection = false;
  for (const section of ['apps', 'displayRoles', 'workspaces', 'modes']) {
    if (!object(config[section])) errors.push(`${section} must be an object`);
    if (!object(config[section])) invalidSection = true;
  }
  if (invalidSection) return { valid: false, errors, warnings };

  if (!Object.keys(config.apps).length) errors.push('apps must not be empty');
  if (!Object.keys(config.displayRoles).length) errors.push('displayRoles must not be empty');
  if (!Object.keys(config.workspaces).length) errors.push('workspaces must not be empty');
  rejectUnknown(config.modes, new Set(MODES), 'modes', errors);
  if (config.shortcuts != null && !Array.isArray(config.shortcuts)) errors.push('shortcuts must be an array');
  if (config.profiles != null && !object(config.profiles)) errors.push('profiles must be an object');
  if (config.rules != null && !Array.isArray(config.rules)) errors.push('rules must be an array');
  if (config.settings != null && !object(config.settings)) errors.push('settings must be an object');
  rejectUnknown(config.settings, new Set(['eventAutomationEnabled', 'topologyStableSamples', 'topologyCooldownSeconds']), 'settings', errors);

  if (config.aiProviders != null && !object(config.aiProviders)) errors.push('aiProviders must be an object');
  if (config.aiRouting != null && !object(config.aiRouting)) errors.push('aiRouting must be an object');
  for (const [providerId, provider] of Object.entries(config.aiProviders || {})) {
    const path = `aiProviders.${providerId}`;
    rejectUnknown(provider, new Set(['name', 'app']), path, errors);
    if (!id(providerId)) errors.push(`${path} has an invalid id`);
    if (!provider?.name?.trim()) errors.push(`${path}.name is required`);
    if (!config.apps[provider?.app]) errors.push(`${path}.app references unknown app "${provider?.app}"`);
  }
  if (config.aiRouting) {
    rejectUnknown(config.aiRouting, new Set(['assignments', 'fallbackWorkspace', 'focusOwner']), 'aiRouting', errors);
    if (!config.workspaces[config.aiRouting.fallbackWorkspace]) errors.push('aiRouting.fallbackWorkspace references an unknown workspace');
    if (typeof config.aiRouting.focusOwner !== 'boolean') errors.push('aiRouting.focusOwner must be boolean');
    for (const [workspaceId, assignment] of Object.entries(config.aiRouting.assignments || {})) {
      const path = `aiRouting.assignments.${workspaceId}`;
      rejectUnknown(assignment, new Set(['role', 'roleOverrides', 'provider', 'overrides']), path, errors);
      const workspace = config.workspaces[workspaceId];
      if (!workspace) errors.push(`${path} references an unknown workspace`);
      if (workspace && !workspace.windows?.[assignment.role]) errors.push(`${path}.role references unknown window role "${assignment.role}"`);
      if (!config.aiProviders?.[assignment.provider]) errors.push(`${path}.provider references unknown AI provider "${assignment.provider}"`);
      rejectUnknown(assignment.overrides, new Set(MODES), `${path}.overrides`, errors);
      rejectUnknown(assignment.roleOverrides, new Set(MODES), `${path}.roleOverrides`, errors);
      for (const [mode, role] of Object.entries(assignment.roleOverrides || {})) {
        if (!workspace?.windows?.[role]) errors.push(`${path}.roleOverrides.${mode} references unknown window role "${role}"`);
        if (workspace && !workspace.variants?.[mode]) errors.push(`${path}.roleOverrides.${mode} targets a mode unavailable to this workspace`);
      }
      for (const [mode, providerId] of Object.entries(assignment.overrides || {})) {
        if (!config.aiProviders?.[providerId]) errors.push(`${path}.overrides.${mode} references unknown AI provider "${providerId}"`);
        if (workspace && !workspace.variants?.[mode]) errors.push(`${path}.overrides.${mode} targets a mode unavailable to this workspace`);
      }
      for (const mode of MODES.filter((item) => workspace?.variants?.[item])) {
        const routedRole = assignment.roleOverrides?.[mode] || assignment.role;
        const variantRoles = (workspace.variants[mode].runtime?.windows || Object.keys(workspace.windows).map((role) => ({ role }))).map((window) => window.role);
        if (!variantRoles.includes(routedRole)) errors.push(`${path} cannot route ${mode}: window role "${routedRole}" is absent from that variant`);
      }
    }
  }

  for (const [profileId, profile] of Object.entries(config.profiles || {})) {
    const path = `profiles.${profileId}`;
    rejectUnknown(profile, new Set(['name', 'mode', 'workspaces', 'displayConfig', 'focusBehaviour', 'settings']), path, errors);
    if (!id(profileId)) errors.push(`${path} has an invalid id`);
    if (!profile?.name?.trim()) errors.push(`${path}.name is required`);
    if (!MODES.includes(profile?.mode)) errors.push(`${path}.mode must be solo, wide, or tall`);
    if (profile.workspaces != null && (!Array.isArray(profile.workspaces) || profile.workspaces.some((item) => !config.workspaces[item]))) errors.push(`${path}.workspaces contains an unknown workspace`);
    if (Array.isArray(profile.workspaces) && MODES.includes(profile.mode) && profile.workspaces.some((item) => config.workspaces[item] && !config.workspaces[item].variants?.[profile.mode])) errors.push(`${path}.workspaces contains a workspace without a ${profile.mode} variant`);
    rejectUnknown(profile.displayConfig, new Set(['profile']), `${path}.displayConfig`, errors);
    rejectUnknown(profile.focusBehaviour, new Set(['workspace']), `${path}.focusBehaviour`, errors);
    rejectUnknown(profile.settings, new Set(['reconcile']), `${path}.settings`, errors);
    if (profile.displayConfig && !['solo', 'wide_left', 'tall_left'].includes(profile.displayConfig.profile)) errors.push(`${path}.displayConfig.profile is unsupported`);
    if (profile.focusBehaviour?.workspace && !config.workspaces[profile.focusBehaviour.workspace]) errors.push(`${path}.focusBehaviour.workspace references an unknown workspace`);
    if (profile.focusBehaviour?.workspace && MODES.includes(profile.mode) && !config.workspaces[profile.focusBehaviour.workspace]?.variants?.[profile.mode]) errors.push(`${path}.focusBehaviour.workspace has no ${profile.mode} variant`);
    if (profile.focusBehaviour?.workspace && profile.workspaces?.length && !profile.workspaces.includes(profile.focusBehaviour.workspace)) errors.push(`${path}.focusBehaviour.workspace must be included in profile.workspaces`);
  }
  const ruleIds = new Set();
  for (const [index, rule] of (config.rules || []).entries()) {
    const path = `rules[${index}]`;
    rejectUnknown(rule, new Set(['id', 'enabled', 'when', 'then']), path, errors);
    rejectUnknown(rule?.when, new Set(['event', 'topology', 'orientation', 'app', 'workspace', 'display', 'layout']), `${path}.when`, errors);
    rejectUnknown(rule?.then, new Set(['activateProfile', 'activateWorkspace', 'mode']), `${path}.then`, errors);
    if (!id(rule?.id)) errors.push(`${path}.id is invalid`);
    else if (ruleIds.has(rule.id)) errors.push(`${path}.id is duplicated`);
    else ruleIds.add(rule.id);
    if (typeof rule?.enabled !== 'boolean') errors.push(`${path}.enabled must be boolean`);
    if (!['display_connected', 'display_disconnected', 'topology_changed', 'wake', 'manual'].includes(rule?.when?.event)) errors.push(`${path}.when.event is unsupported`);
    if (rule?.when?.app && !config.apps[rule.when.app]) errors.push(`${path}.when.app references an unknown app`);
    if (rule?.when?.workspace && !config.workspaces[rule.when.workspace]) errors.push(`${path}.when.workspace references an unknown workspace`);
    if (rule?.when?.display && !config.displayRoles[rule.when.display]) errors.push(`${path}.when.display references an unknown display role`);
    if (rule?.then?.activateProfile && !config.profiles?.[rule.then.activateProfile]) errors.push(`${path}.then.activateProfile references an unknown profile`);
    if (rule?.then?.activateWorkspace && !config.workspaces[rule.then.activateWorkspace]) errors.push(`${path}.then.activateWorkspace references an unknown workspace`);
    if (rule?.then?.activateWorkspace && !rule.then.mode) errors.push(`${path}.then.mode is required when activating a workspace`);
    if (rule?.then?.activateWorkspace && rule.then.mode && !config.workspaces[rule.then.activateWorkspace]?.variants?.[rule.then.mode]) errors.push(`${path}.then.activateWorkspace has no ${rule.then.mode} variant`);
    if (rule?.then?.mode && !MODES.includes(rule.then.mode)) errors.push(`${path}.then.mode is unsupported`);
    if (!rule?.then?.activateProfile && !rule?.then?.activateWorkspace) errors.push(`${path}.then must activate a profile or workspace`);
  }

  const appAliases = new Map();
  for (const [appId, app] of Object.entries(config.apps)) {
    rejectUnknown(app, new Set(['name', 'match']), `apps.${appId}`, errors);
    rejectUnknown(app?.match, new Set(['appNames', 'bundleIds']), `apps.${appId}.match`, errors);
    if (!id(appId)) errors.push(`apps.${appId} has an invalid id`);
    if (!app?.name?.trim()) errors.push(`apps.${appId}.name is required`);
    if (!Array.isArray(app?.match?.appNames) || !app.match.appNames.length || app.match.appNames.some((name) => typeof name !== 'string' || !name.trim())) {
      errors.push(`apps.${appId}.match.appNames must contain at least one name`);
    }
    if (app?.match?.bundleIds != null && (!Array.isArray(app.match.bundleIds) || app.match.bundleIds.some((bundleId) => typeof bundleId !== 'string' || !bundleId.trim()))) errors.push(`apps.${appId}.match.bundleIds must be an array of non-empty strings`);
    for (const name of app?.match?.appNames || []) {
      const normalized = name.toLocaleLowerCase();
      if (appAliases.has(normalized) && appAliases.get(normalized) !== appId) warnings.push(`apps.${appId}.match.appNames shares “${name}” with apps.${appAliases.get(normalized)}`);
      else appAliases.set(normalized, appId);
    }
  }
  for (const [roleId, role] of Object.entries(config.displayRoles)) {
    rejectUnknown(role, new Set(['name', 'portableMatch']), `displayRoles.${roleId}`, errors);
    rejectUnknown(role?.portableMatch, new Set(['builtIn', 'orientation']), `displayRoles.${roleId}.portableMatch`, errors);
    if (!id(roleId)) errors.push(`displayRoles.${roleId} has an invalid id`);
    if (!role?.name?.trim()) errors.push(`displayRoles.${roleId}.name is required`);
  }
  const labels = new Map();
  for (const [workspaceId, workspace] of Object.entries(config.workspaces)) {
    const path = `workspaces.${workspaceId}`;
    rejectUnknown(workspace, new Set(['name', 'spaceLabel', 'windows', 'variants']), path, errors);
    if (!id(workspaceId)) errors.push(`${path} has an invalid id`);
    if (!workspace?.name?.trim()) errors.push(`${path}.name is required`);
    if (!workspace?.spaceLabel?.trim()) errors.push(`${path}.spaceLabel is required`);
    else if (labels.has(workspace.spaceLabel)) errors.push(`${path}.spaceLabel duplicates workspaces.${labels.get(workspace.spaceLabel)}.spaceLabel`);
    else labels.set(workspace.spaceLabel, workspaceId);
    if (!object(workspace?.windows) || !Object.keys(workspace.windows).length) errors.push(`${path}.windows must not be empty`);
    const roles = new Set(Object.keys(workspace?.windows || {}));
    for (const [role, window] of Object.entries(workspace?.windows || {})) {
      rejectUnknown(window, new Set(['app', 'required', 'ownership', 'cardinality', 'selector']), `${path}.windows.${role}`, errors);
      rejectUnknown(window?.selector, new Set(['movable', 'visible', 'non_empty_title', 'title_include', 'title_exclude', 'role', 'subrole']), `${path}.windows.${role}.selector`, errors);
      if (!id(role)) errors.push(`${path}.windows.${role} has an invalid id`);
      if (!config.apps[window.app]) errors.push(`${path}.windows.${role}.app references unknown app "${window.app}"`);
      if (typeof window.required !== 'boolean') errors.push(`${path}.windows.${role}.required must be boolean`);
      if (window.ownership != null && !['lastApplicable', 'independent'].includes(window.ownership)) errors.push(`${path}.windows.${role}.ownership is invalid`);
      if (window.cardinality != null && !['one', 'many'].includes(window.cardinality)) errors.push(`${path}.windows.${role}.cardinality is invalid`);
      for (const flag of ['movable', 'visible', 'non_empty_title']) if (window.selector?.[flag] != null && typeof window.selector[flag] !== 'boolean') errors.push(`${path}.windows.${role}.selector.${flag} must be boolean`);
      for (const field of ['title_include', 'title_exclude']) if (window.selector?.[field] != null && typeof window.selector[field] !== 'string') errors.push(`${path}.windows.${role}.selector.${field} must be a string`);
      for (const field of ['role', 'subrole']) if (window.selector?.[field] != null && (typeof window.selector[field] !== 'string' || !window.selector[field].trim())) errors.push(`${path}.windows.${role}.selector.${field} must be a non-empty string`);
    }
    if (!object(workspace?.variants)) errors.push(`${path}.variants must be an object`);
    for (const [mode, variant] of Object.entries(workspace?.variants || {})) {
      rejectUnknown(variant, new Set(['layout', 'command', 'spaceLabel', 'activation', 'runtime']), `${path}.variants.${mode}`, errors);
      if (!MODES.includes(mode)) errors.push(`${path}.variants.${mode} is not a supported mode`);
      const usedRoles = new Set();
      validateLayout(variant.layout, `${path}.variants.${mode}.layout`, roles, errors, usedRoles);
      if (variant.activation?.type === 'windowPresent' && !roles.has(variant.activation.role)) errors.push(`${path}.variants.${mode}.activation.role references unknown window role "${variant.activation.role}"`);
      for (const [role, window] of Object.entries(workspace.windows || {})) {
        if (window.required && !usedRoles.has(role)) errors.push(`${path}.variants.${mode}.layout omits required window role "${role}"`);
        else if (!window.required && !usedRoles.has(role)) warnings.push(`${path}.variants.${mode}.layout does not place optional window role "${role}"`);
      }
      if (variant.runtime?.windows) {
        if (!Array.isArray(variant.runtime.windows) || !variant.runtime.windows.length) errors.push(`${path}.variants.${mode}.runtime.windows must not be empty`);
        const runtimeRoles = new Set();
        for (const [index, window] of (variant.runtime.windows || []).entries()) {
          if (!id(window.role)) errors.push(`${path}.variants.${mode}.runtime.windows[${index}].role is invalid`);
          if (runtimeRoles.has(window.role)) errors.push(`${path}.variants.${mode}.runtime.windows duplicates role "${window.role}"`);
          runtimeRoles.add(window.role);
          if (!config.apps[window.app_key]) errors.push(`${path}.variants.${mode}.runtime.windows[${index}].app_key references an unknown app`);
          if (typeof window.required !== 'boolean') errors.push(`${path}.variants.${mode}.runtime.windows[${index}].required must be boolean`);
          if (window.ownership != null && !['lastApplicable', 'independent'].includes(window.ownership)) errors.push(`${path}.variants.${mode}.runtime.windows[${index}].ownership is invalid`);
          if (window.cardinality != null && !['one', 'many'].includes(window.cardinality)) errors.push(`${path}.variants.${mode}.runtime.windows[${index}].cardinality is invalid`);
        }
        for (const role of usedRoles) if (!runtimeRoles.has(role)) errors.push(`${path}.variants.${mode}.runtime.windows omits layout role "${role}"`);
        if (variant.activation?.type === 'windowPresent' && !runtimeRoles.has(variant.activation.role)) errors.push(`${path}.variants.${mode}.runtime.windows omits activation role "${variant.activation.role}"`);
      }
    }
  }
  for (const mode of MODES) {
    const definition = config.modes[mode];
    if (!definition) continue;
    rejectUnknown(definition, new Set(['displays', 'cleanup', 'contextualApps', 'postprocessors']), `modes.${mode}`, errors);
    if (!Array.isArray(definition.displays) || !definition.displays.length) errors.push(`modes.${mode}.displays must not be empty`);
    const placed = new Set();
    const modeLabels = new Map();
    for (const [index, display] of (definition.displays || []).entries()) {
      rejectUnknown(display, new Set(['role', 'workspaceOrder']), `modes.${mode}.displays[${index}]`, errors);
      if (!config.displayRoles[display.role]) errors.push(`modes.${mode}.displays[${index}].role references unknown display role "${display.role}"`);
      if (!Array.isArray(display.workspaceOrder)) errors.push(`modes.${mode}.displays[${index}].workspaceOrder must be an array`);
      for (const workspaceId of display.workspaceOrder || []) {
        const workspace = config.workspaces[workspaceId];
        if (!workspace) errors.push(`modes.${mode} references unknown workspace "${workspaceId}"`);
        else if (!workspace.variants?.[mode]) errors.push(`workspace "${workspaceId}" has no ${mode} variant`);
        if (placed.has(workspaceId)) errors.push(`workspace "${workspaceId}" appears twice in ${mode}`);
        placed.add(workspaceId);
        if (workspace?.variants?.[mode]) {
          const label = workspace.variants[mode].spaceLabel || `${workspace.spaceLabel}_${mode}`;
          if (modeLabels.has(label)) errors.push(`modes.${mode} produces duplicate Space label "${label}" for workspaces "${modeLabels.get(label)}" and "${workspaceId}"`);
          else modeLabels.set(label, workspaceId);
        }
      }
    }
    for (const workspaceId of Object.keys(config.workspaces)) {
      if (config.workspaces[workspaceId].variants?.[mode] && !placed.has(workspaceId)) warnings.push(`workspaces.${workspaceId}.variants.${mode} is not used by modes.${mode}`);
    }
    const routedProviderApps = new Set([...placed].map((workspaceId) => {
      const providerId = config.aiRouting?.assignments?.[workspaceId]?.overrides?.[mode] || config.aiRouting?.assignments?.[workspaceId]?.provider;
      return config.aiProviders?.[providerId]?.app;
    }).filter(Boolean));
    if (routedProviderApps.size) {
      const fallbackId = config.aiRouting.fallbackWorkspace;
      if (!placed.has(fallbackId)) errors.push(`aiRouting.fallbackWorkspace "${fallbackId}" is outside ${mode}`);
      const fallbackWorkspace = config.workspaces[fallbackId];
      const fallbackWindows = fallbackWorkspace?.variants?.[mode]?.runtime?.windows || Object.values(fallbackWorkspace?.windows || {}).map((window) => ({ app_key: window.app }));
      const fallbackApps = new Set(fallbackWindows.map((window) => window.app_key));
      const fallbackProviderId = config.aiRouting.assignments?.[fallbackId]?.overrides?.[mode] || config.aiRouting.assignments?.[fallbackId]?.provider;
      if (config.aiProviders?.[fallbackProviderId]?.app) fallbackApps.add(config.aiProviders[fallbackProviderId].app);
      for (const appKey of routedProviderApps) if (!fallbackApps.has(appKey)) errors.push(`aiRouting fallback workspace "${fallbackId}" does not contain provider app "${appKey}" in ${mode}`);
    }
    if (definition.cleanup && (!Array.isArray(definition.cleanup) || definition.cleanup.some((item) => typeof item !== 'string' || !/^[a-z_]+:(solo|wide|tall)$/.test(item)))) errors.push(`modes.${mode}.cleanup is invalid`);
    for (const [index, rule] of (Array.isArray(definition.contextualApps) ? definition.contextualApps : []).entries()) {
      const path = `modes.${mode}.contextualApps[${index}]`;
      if (!config.apps[rule.app]) errors.push(`${path}.app references unknown app "${rule.app}"`);
      if (!Array.isArray(rule.workspaces) || !rule.workspaces.length) errors.push(`${path}.workspaces must not be empty`);
      for (const workspaceId of rule.workspaces || []) {
        if (!placed.has(workspaceId)) errors.push(`${path}.workspaces references workspace "${workspaceId}" outside ${mode}`);
        const windows = config.workspaces[workspaceId]?.variants?.[mode]?.runtime?.windows || Object.entries(config.workspaces[workspaceId]?.windows || {}).map(([role, window]) => ({ role, app_key: window.app }));
        if (!windows.some((window) => window.app_key === rule.app)) errors.push(`${path} app "${rule.app}" is not present in workspace "${workspaceId}"`);
      }
      if (!rule.workspaces?.includes(rule.fallbackWorkspace)) errors.push(`${path}.fallbackWorkspace must be listed in workspaces`);
    }
    for (const [index, hook] of (definition.postprocessors || []).entries()) {
      if (!POSTPROCESSORS.has(hook.name)) errors.push(`modes.${mode}.postprocessors[${index}] is unsupported`);
      if (hook.afterCommand != null && typeof hook.afterCommand !== 'string') errors.push(`modes.${mode}.postprocessors[${index}].afterCommand must be a string or null`);
    }
  }
  const chords = new Set();
  for (const [index, shortcut] of (Array.isArray(config.shortcuts) ? config.shortcuts : []).entries()) {
    rejectUnknown(shortcut, new Set(['id', 'keys', 'action']), `shortcuts[${index}]`, errors);
    rejectUnknown(shortcut.keys, new Set(['modifiers', 'key']), `shortcuts[${index}].keys`, errors);
    rejectUnknown(shortcut.action, new Set(shortcut.action?.type === 'activateWorkspace' ? ['type', 'workspace', 'mode'] : ['type', 'mode']), `shortcuts[${index}].action`, errors);
    if (typeof shortcut.id !== 'string' || !shortcut.id) errors.push(`shortcuts[${index}].id is required`);
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
  return { valid: errors.length === 0, errors, warnings };
}

export function compileLayout(node, rect = { x: 0, y: 0, w: 120, h: 120 }, actions = []) {
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

export function resolvedAIProvider(config, workspaceId, mode) {
  const assignment = config.aiRouting?.assignments?.[workspaceId];
  return assignment ? (assignment.overrides?.[mode] || assignment.provider) : null;
}

export function resolvedAIRole(config, workspaceId, mode) {
  const assignment = config.aiRouting?.assignments?.[workspaceId];
  return assignment ? (assignment.roleOverrides?.[mode] || assignment.role) : null;
}

function configuredWindows(config, workspaceId, mode) {
  const workspace = config.workspaces[workspaceId];
  const variant = workspace.variants[mode];
  const windows = structuredClone(variant.runtime?.windows || Object.entries(workspace.windows).map(([role, window]) => ({
    role, app_key: window.app, required: window.required,
    ...(window.ownership ? { ownership: window.ownership } : {}),
    ...(window.cardinality ? { cardinality: window.cardinality } : {}),
    ...(window.selector ? { selector: window.selector } : {})
  })));
  const assignment = config.aiRouting?.assignments?.[workspaceId];
  const providerId = resolvedAIProvider(config, workspaceId, mode);
  const providerApp = config.aiProviders?.[providerId]?.app;
  if (assignment && providerApp) {
    const routed = windows.find((window) => window.role === resolvedAIRole(config, workspaceId, mode));
    if (routed) routed.app_key = providerApp;
  }
  return windows;
}

export function compileContextualApps(config, mode) {
  const placed = config.modes[mode]?.displays.flatMap((display) => display.workspaceOrder) || [];
  const fallback = config.aiRouting?.fallbackWorkspace;
  const grouped = new Map();
  for (const workspaceId of placed) {
    const providerId = resolvedAIProvider(config, workspaceId, mode);
    const appKey = config.aiProviders?.[providerId]?.app;
    if (!appKey) continue;
    const workspaces = grouped.get(appKey) || [];
    workspaces.push(workspaceId);
    grouped.set(appKey, workspaces);
  }
  const derived = [...grouped].map(([appKey, workspaces]) => ({
    app_key: appKey,
    workspace_ids: [...new Set([...workspaces, ...(fallback && placed.includes(fallback) ? [fallback] : [])])],
    fallback_workspace_id: fallback,
    focus_owner: config.aiRouting?.focusOwner === true
  }));
  const derivedApps = new Set(derived.map((rule) => rule.app_key));
  const manual = (config.modes[mode]?.contextualApps || [])
    .filter((rule) => !derivedApps.has(rule.app))
    .map((rule) => ({ app_key: rule.app, workspace_ids: rule.workspaces, fallback_workspace_id: rule.fallbackWorkspace, focus_owner: rule.focusOwner === true }));
  return [...derived, ...manual];
}

export function compileV2(config) {
  const validation = validateV2(config);
  if (!validation.valid) throw new Error(validation.errors.join('\n'));
  const runtime = { version: 1, source_version: 2, apps: {}, display_roles: {}, layouts: {}, workspaces: {}, modes: {}, profiles: config.profiles || {}, rules: (config.rules || []).filter((rule) => rule.enabled), settings: config.settings || {} };
  for (const [appId, app] of Object.entries(config.apps)) runtime.apps[appId] = { names: app.match.appNames, ...(app.match.bundleIds?.length ? { bundle_ids: app.match.bundleIds } : {}) };
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
          activation: structuredClone(variant.activation || { type: 'always' }),
          windows: configuredWindows(config, workspaceId, mode),
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
    runtime.modes[`work_${mode}`] = {
      display_mode: mode,
      steps,
      cleanup: config.modes[mode]?.cleanup || [],
      contextual_apps: compileContextualApps(config, mode)
    };
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
      target.windows[role] = {
        app: window.app_key,
        required: window.required,
        ...(window.ownership ? { ownership: window.ownership } : {}),
        ...((window.cardinality || (source.runner === 'gtd_support' && window.role === 'dia' ? 'many' : null)) ? { cardinality: window.cardinality || 'many' } : {}),
        ...(window.selector ? { selector: window.selector } : {})
      };
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
        ...(entry.source.runner === 'office_document' ? { activation: { type: 'windowPresent', role: 'primary' } } : {}),
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
      ? `spacewright mode ${shortcut.action.mode}`
      : `spacewright run ${shortcut.action.workspace} ${shortcut.action.mode}`;
    lines.push(`${chord}${chord ? ' - ' : ''}${shortcut.keys.key} : fish -lc '${command}'`);
  }
  return `${lines.join('\n')}\n`;
}
