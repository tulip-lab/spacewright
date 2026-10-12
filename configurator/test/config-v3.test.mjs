import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import {
  compileV3,
  compileSkhdV3,
  describeDisplays,
  hardwareFamilyFromModel,
  matchingSetups,
  migrateV2ToV3,
  projectSetupToV2,
  resolveV3,
  starterV3,
  topologyKey,
  validateV3
} from '../lib/config-v3.mjs';
import { starterConfig } from '../lib/config-v2.mjs';
import { detectMacHardware } from '../lib/hardware-detection.mjs';

const snapshot = (displays) => ({ unavailable: false, displays });
const machine = (hardwareProfile, bindings, extra = {}) => ({
  version: 2,
  hardwareProfile,
  hardwareProfileConfirmed: true,
  displayBindings: bindings,
  displayKinds: {},
  topologySelections: {},
  ...extra
});

test('v3 schema is valid JSON and starter validates', async () => {
  const schema = JSON.parse(await readFile(new URL('../../schemas/spacewright-v3.schema.json', import.meta.url), 'utf8'));
  assert.equal(schema.properties.version.const, 3);
  const result = validateV3(starterV3());
  assert.equal(result.valid, true, result.errors.join('\n'));
  const malformed = starterV3();
  malformed.hardwareProfiles.mac_mini.setups.single_tall.match.displays = {};
  assert.match(validateV3(malformed).errors.join('\n'), /must be array/);
});

test('hardware family uses model identity rather than display presence', () => {
  assert.equal(hardwareFamilyFromModel('MacBookPro18,3'), 'macbook');
  assert.equal(hardwareFamilyFromModel('Macmini9,1'), 'mac_mini');
  assert.equal(hardwareFamilyFromModel('Mac14,8'), 'other');
  assert.equal(hardwareFamilyFromModel('Mac16,10', 'Mac mini'), 'mac_mini');
});

test('generic Apple model identifiers use the system product name', async () => {
  const hardware = await detectMacHardware({ modelIdentifier: 'Mac16,10', productName: 'Mac mini', allowSystemProfiler: false });
  assert.equal(hardware.family, 'mac_mini');
  assert.equal(hardware.productName, 'Mac mini');
});

test('Mac mini single tall resolves only after confirmation', () => {
  const config = starterV3();
  const displays = snapshot([{ index: 1, uuid: 'TALL', frame: { w: 1200, h: 1920 }, builtIn: false }]);
  const local = machine('mac_mini', { tall: 'TALL' });
  assert.deepEqual(matchingSetups(config, 'mac_mini', displays, local), ['single_tall']);
  assert.throws(() => resolveV3(config, { machine: local, snapshot: displays }), /requires confirmation/);
  local.topologySelections['external:tall'] = 'single_tall';
  const resolved = resolveV3(config, { machine: local, snapshot: displays });
  assert.equal(resolved.setupId, 'single_tall');
  assert.equal(resolved.v2.workspaces.coding.variants.tall.command, 'spacewright_coding_tall');
  const runtime = compileV3(config, resolved);
  assert.equal(runtime.source_version, 3);
  assert.equal(runtime.active_hardware_profile, 'mac_mini');
  assert.equal(runtime.active_setup, 'single_tall');
});

test('Mac mini wide plus tall and external plus Sidecar are distinct topologies', () => {
  const config = starterV3();
  const wideTall = snapshot([
    { index: 1, uuid: 'WIDE', frame: { w: 1920, h: 1080 }, builtIn: false },
    { index: 2, uuid: 'TALL', frame: { w: 1080, h: 1920 }, builtIn: false }
  ]);
  const local = machine('mac_mini', { wide: 'WIDE', tall: 'TALL' });
  assert.equal(topologyKey(describeDisplays(wideTall, local)), 'external:tall+external:wide');
  assert.deepEqual(matchingSetups(config, 'mac_mini', wideTall, local), ['wide_tall']);

  const sidecar = snapshot([
    { index: 1, uuid: 'WIDE', frame: { w: 1920, h: 1080 }, builtIn: false },
    { index: 2, uuid: 'IPAD', frame: { w: 1024, h: 1366 }, builtIn: false }
  ]);
  const withSidecar = machine('mac_mini', { wide: 'WIDE', sidecar: 'IPAD' }, { displayKinds: { IPAD: 'sidecar' } });
  assert.deepEqual(matchingSetups(config, 'mac_mini', sidecar, withSidecar), ['wide_sidecar']);
});

test('MacBook profiles distinguish built-in plus Sidecar topologies', () => {
  const config = starterV3();
  const displays = snapshot([
    { index: 1, uuid: 'BUILTIN', frame: { w: 1728, h: 1117 }, builtIn: true },
    { index: 2, uuid: 'IPAD', frame: { w: 1024, h: 1366 }, builtIn: false }
  ]);
  const local = machine('macbook', { built_in: 'BUILTIN', sidecar: 'IPAD' }, { displayKinds: { IPAD: 'sidecar' } });
  assert.deepEqual(matchingSetups(config, 'macbook', displays, local), ['built_in_sidecar']);
});

test('ambiguous and unavailable observations fail closed', () => {
  const config = starterV3();
  const local = machine('mac_mini', { wide: 'WIDE' });
  assert.throws(() => resolveV3(config, { machine: local, snapshot: { unavailable: true, message: 'query failed', displays: [] } }), /query failed/);
  config.hardwareProfiles.mac_mini.setups.copy = structuredClone(config.hardwareProfiles.mac_mini.setups.single_wide);
  const displays = snapshot([{ index: 1, uuid: 'WIDE', frame: { w: 1920, h: 1080 }, builtIn: false }]);
  assert.throws(() => resolveV3(config, { machine: local, snapshot: displays, requireConfirmation: false }), /ambiguous/);
});

test('v2 migration preserves variants as named configurations', () => {
  const source = starterConfig();
  const migrated = migrateV2ToV3(source);
  assert.equal(migrated.version, 3);
  assert.deepEqual(Object.keys(migrated.workspaces.coding.configurations).sort(), ['mac_mini_single_tall', 'solo', 'tall', 'wide']);
  assert.equal(migrated.hardwareProfiles.macbook.setups.wide.workspaceConfigurations.coding, 'wide');
  assert.ok(migrated.hardwareProfiles.macbook.setups.built_in_wide_sidecar);
  assert.equal(validateV3(migrated).valid, true, validateV3(migrated).errors.join('\n'));
});

test('v2 migration places every workspace in every hardware setup', () => {
  const source = starterConfig();
  source.modes.tall.displays[0].workspaceOrder = [];
  const migrated = migrateV2ToV3(source);
  const expected = Object.keys(source.workspaces).sort();
  for (const profile of Object.values(migrated.hardwareProfiles)) {
    for (const setup of Object.values(profile.setups)) {
      const placed = setup.lanes.flatMap((lane) => lane.workspaceOrder);
      assert.deepEqual([...placed].sort(), expected);
      assert.equal(new Set(placed).size, expected.length);
      assert.deepEqual(Object.keys(setup.workspaceConfigurations).sort(), expected);
    }
  }
  assert.equal(migrated.hardwareProfiles.mac_mini.setups.single_tall.workspaceConfigurations.coding, 'mac_mini_single_tall');
  assert.equal(migrated.workspaces.coding.configurations.mac_mini_single_tall.runtime.displayRole, 'task');
  assert.equal(validateV3(migrated).valid, true, validateV3(migrated).errors.join('\n'));
});

test('setup projection selects workspace configuration explicitly', () => {
  const config = starterV3();
  const projected = projectSetupToV2(config, 'mac_mini', 'single_wide');
  assert.ok(projected.workspaces.coding.variants.wide);
  assert.equal(projected.workspaces.coding.variants.wide.spaceLabel, 'coding_wide');
  assert.deepEqual(projected.modes.wide.displays[0].workspaceOrder, ['coding']);
});

test('v3 shortcuts keep workspace selection hardware-aware', () => {
  const config = starterV3();
  config.shortcuts.push({ id: 'coding', keys: { modifiers: ['alt'], key: '1' }, action: { type: 'activateWorkspace', workspace: 'coding' } });
  const displays = snapshot([{ index: 1, uuid: 'TALL', frame: { w: 1200, h: 1920 }, builtIn: false }]);
  const local = machine('mac_mini', { tall: 'TALL' }, { topologySelections: { 'external:tall': 'single_tall' } });
  const fragment = compileSkhdV3(config, { machine: local, snapshot: displays });
  assert.match(fragment, /spacewright workspace coding'/);
  assert.doesNotMatch(fragment, /workspace coding tall/);
});
