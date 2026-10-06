import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { CONFIG_COMPILER_VERSION, compileSkhd, compileV2, migrateV1, starterConfig, validateV2, validateV2Schema } from '../lib/config-v2.mjs';

const MODES_FOR_TEST = ['solo', 'wide', 'tall'];

test('starter config validates and compiles all modes', () => {
  const config = starterConfig();
  assert.equal(validateV2(config).valid, true);
  const runtime = compileV2(config);
  assert.equal(runtime.version, 1);
  assert.equal(runtime.workspaces.spacewright_coding_wide.runner, 'generic_layout');
  assert.deepEqual(runtime.layouts.spacewright_coding_wide, [
    { role: 'assistant', grid: '120:120:0:0:40:120' },
    { role: 'editor', grid: '120:120:40:0:80:120' }
  ]);
  assert.deepEqual(runtime.modes.work_tall.steps, [{ workspace: 'spacewright_coding_tall' }]);
});

test('profiles and event rules validate and compile as declarative automation', () => {
  const config = starterConfig();
  config.profiles = { research: { name: 'Research', mode: 'wide', workspaces: ['coding'], displayConfig: { profile: 'wide_left' }, focusBehaviour: { workspace: 'coding' }, settings: { reconcile: true } } };
  config.rules = [{ id: 'external_research', enabled: true, when: { event: 'display_connected', topology: 'wide_left' }, then: { activateProfile: 'research' } }];
  config.settings = { eventAutomationEnabled: false, topologyStableSamples: 3, topologyCooldownSeconds: 30 };
  assert.equal(validateV2(config).valid, true);
  const runtime = compileV2(config);
  assert.equal(runtime.profiles.research.mode, 'wide');
  assert.equal(runtime.rules[0].then.activateProfile, 'research');
});

test('validation rejects unknown fields, duplicate labels, and omitted required roles', () => {
  const config = starterConfig();
  config.scripts = ['unsafe'];
  config.workspaces.second = structuredClone(config.workspaces.coding);
  config.workspaces.second.variants.wide.layout = { type: 'window', role: 'assistant' };
  const result = validateV2(config);
  assert.equal(result.valid, false);
  assert.match(result.errors.join('\n'), /\$\.scripts is not supported/);
  assert.match(result.errors.join('\n'), /spaceLabel duplicates/);
  assert.match(result.errors.join('\n'), /omits required window role "editor"/);
});

test('repository schema is the structural validation authority', () => {
  const config = starterConfig();
  config.apps.code.match.appNames = [];
  config.workspaces.coding.variants.wide.layout.extra = true;
  const errors = validateV2Schema(config).join('\n');
  assert.match(errors, /apps.code.match.appNames must contain at least 1 item/);
  assert.match(errors, /workspaces.coding.variants.wide.layout does not match a supported shape/);
  assert.equal(CONFIG_COMPILER_VERSION, 2);
});

test('nested split compiles deterministically', () => {
  const config = starterConfig();
  config.workspaces.coding.variants.wide.layout = {
    type: 'split', direction: 'columns', weights: [1, 2], children: [
      { type: 'window', role: 'assistant' },
      { type: 'split', direction: 'rows', weights: [1, 1], children: [
        { type: 'window', role: 'editor' }, { type: 'empty' }
      ] }
    ]
  };
  assert.deepEqual(compileV2(config).layouts.spacewright_coding_wide, [
    { role: 'assistant', grid: '120:120:0:0:40:120' },
    { role: 'editor', grid: '120:120:40:0:80:60' }
  ]);
});

test('activation, ownership, and cardinality remain declarative through compilation', () => {
  const config = starterConfig();
  config.workspaces.coding.windows.assistant.ownership = 'independent';
  config.workspaces.coding.windows.assistant.cardinality = 'many';
  config.workspaces.coding.variants.wide.activation = { type: 'windowPresent', role: 'editor' };
  assert.equal(validateV2(config).valid, true);
  const runtime = compileV2(config);
  assert.equal(runtime.workspaces.spacewright_coding_wide.windows.find((window) => window.role === 'assistant').ownership, 'independent');
  assert.equal(runtime.workspaces.spacewright_coding_wide.windows.find((window) => window.role === 'assistant').cardinality, 'many');
  config.workspaces.coding.variants.wide.activation.role = 'unknown';
  assert.match(validateV2(config).errors.join('\n'), /activation\.role references unknown window role/);
});

test('contextual apps validate and compile as a closed mode policy', () => {
  const config = starterConfig();
  config.modes.solo.contextualApps = [{ app: 'chatgpt', workspaces: ['coding'], fallbackWorkspace: 'coding', focusOwner: true }];
  assert.equal(validateV2(config).valid, true);
  assert.deepEqual(compileV2(config).modes.work_solo.contextual_apps, [{
    app_key: 'chatgpt', workspace_ids: ['coding'], fallback_workspace_id: 'coding', focus_owner: true
  }]);
  config.modes.solo.contextualApps[0].workspaces = ['missing'];
  assert.match(validateV2(config).errors.join('\n'), /outside solo/);
});

test('runtime window overrides reject duplicate and omitted layout roles', () => {
  const config = starterConfig();
  config.workspaces.coding.variants.wide.runtime = {
    runner: 'generic_layout',
    windows: [
      { role: 'editor', app_key: 'code', required: true },
      { role: 'editor', app_key: 'chatgpt', required: false }
    ]
  };
  const errors = validateV2(config).errors.join('\n');
  assert.match(errors, /runtime\.windows duplicates role "editor"/);
  assert.match(errors, /runtime\.windows omits layout role "assistant"/);
});

test('duplicate shortcuts fail closed', () => {
  const config = starterConfig();
  config.shortcuts.push(structuredClone(config.shortcuts[0]));
  assert.equal(validateV2(config).valid, false);
});

test('skhd output contains only closed actions', () => {
  const output = compileSkhd(starterConfig());
  assert.match(output, /fish -lc 'spacewright mode wide'/);
  assert.doesNotMatch(output, /undefined/);
});

test('skhd output includes workspace actions and rejects an exact chord conflict', () => {
  const config = starterConfig();
  config.shortcuts.push({
    id: 'coding-wide',
    keys: { modifiers: ['ctrl', 'alt'], key: 'c' },
    action: { type: 'activateWorkspace', workspace: 'coding', mode: 'wide' }
  });
  assert.match(compileSkhd(config), /ctrl \+ alt - c : fish -lc 'spacewright run coding wide'/);
  config.shortcuts.push({
    id: 'coding-wide-duplicate',
    keys: { modifiers: ['alt', 'ctrl'], key: 'c' },
    action: { type: 'activateMode', mode: 'solo' }
  });
  assert.match(validateV2(config).errors.join('\n'), /shortcut chord alt\+ctrl\+c is duplicated/);
});

test('v1 migration preserves command, runner, label, and grid', () => {
  const v1 = {
    version: 1,
    apps: { code: { names: ['Code'] } },
    layouts: { coding_wide: [{ role: 'editor', grid: '1:3:1:0:2:1' }] },
    workspaces: { coding_wide: { runner: 'primary_helper', label: 'coding_wide', display_role: 'wide', space_layout: 'float', windows: [{ role: 'editor', app_key: 'code', required: true }], layout_ref: 'coding_wide' } },
    modes: { work_wide: { display_mode: 'wide', steps: [{ workspace: 'coding_wide' }] }, work_solo: { display_mode: 'solo', steps: [] }, work_tall: { display_mode: 'tall', steps: [] } }
  };
  const migrated = migrateV1(v1);
  assert.equal(validateV2(migrated).valid, true);
  const runtime = compileV2(migrated);
  assert.equal(runtime.workspaces.coding_wide.runner, 'primary_helper');
  assert.equal(runtime.workspaces.coding_wide.label, 'coding_wide');
  assert.deepEqual(runtime.layouts.coding_wide, v1.layouts.coding_wide);
});

function expandModeSteps(config, modeId, seen = new Set()) {
  if (seen.has(modeId)) throw new Error(`mode cycle: ${modeId}`);
  seen.add(modeId);
  const result = [];
  for (const step of config.modes[modeId].steps) {
    if (step.mode) result.push(...expandModeSteps(config, step.mode, seen));
    else result.push(step);
  }
  seen.delete(modeId);
  return result;
}

test('repository v1 migration preserves every workspace layout and top-level mode semantics', async () => {
  const defaults = JSON.parse(await readFile(new URL('../../config/defaults.json', import.meta.url), 'utf8'));
  const runtime = compileV2(migrateV1(defaults));
  assert.deepEqual(Object.keys(runtime.workspaces).sort(), Object.keys(defaults.workspaces).sort());
  for (const [id, workspace] of Object.entries(defaults.workspaces)) {
    assert.equal(runtime.workspaces[id].runner, workspace.runner, `${id} runner`);
    assert.equal(runtime.workspaces[id].label, workspace.label, `${id} label`);
    assert.equal(runtime.workspaces[id].display_role, workspace.display_role, `${id} display role`);
    assert.deepEqual(runtime.workspaces[id].windows, workspace.windows, `${id} windows`);
    assert.deepEqual(runtime.layouts[runtime.workspaces[id].layout_ref], defaults.layouts[workspace.layout_ref], `${id} layout`);
  }
  for (const mode of MODES_FOR_TEST) {
    assert.deepEqual(runtime.modes[`work_${mode}`].steps, expandModeSteps(defaults, `work_${mode}`), `${mode} steps`);
    assert.deepEqual(runtime.modes[`work_${mode}`].cleanup, defaults.modes[`work_${mode}`].cleanup, `${mode} cleanup`);
  }
});
