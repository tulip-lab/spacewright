#!/usr/bin/env node

import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { existsSync } from 'node:fs';
import { mkdir, readFile, rename, writeFile } from 'node:fs/promises';
import { dirname, join, resolve } from 'node:path';
import { createHash } from 'node:crypto';
import { CONFIG_COMPILER_VERSION } from './lib/config-v2.mjs';
import {
  compileV3,
  describeDisplays,
  matchingSetups,
  selectHardwareProfile,
  setupBindingStatus,
  topologyKey,
  validateV3
} from './lib/config-v3.mjs';
import { generationDocument, withConfigurationWrite, stableRead } from './lib/config-store.mjs';
import { detectMacHardware } from './lib/hardware-detection.mjs';

const execFileAsync = promisify(execFile);
const command = process.argv[2] || 'status';
const positional = process.argv.slice(3).filter((value) => !value.startsWith('--'));
const flags = Object.fromEntries(process.argv.slice(3).filter((value) => value.startsWith('--')).map((value) => {
  const [key, ...rest] = value.slice(2).split('=');
  return [key, rest.length ? rest.join('=') : true];
}));
const configRoot = resolve(flags['config-root'] || process.env.SPACEWRIGHT_CONFIG_ROOT || join(process.env.HOME, '.config', 'spacewright'));
const stateRoot = resolve(flags['state-root'] || process.env.SPACEWRIGHT_STATE_ROOT || join(process.env.HOME, '.local', 'state', 'spacewright'));
const configFile = resolve(flags.config || join(configRoot, 'config.v3.json'));
const machineFile = join(stateRoot, 'machine.json');
const runtimeFile = resolve(flags.runtime || join(configRoot, 'generated', 'runtime.json'));

async function readJson(path, fallback) {
  if (!existsSync(path)) return structuredClone(fallback);
  return JSON.parse(await readFile(path, 'utf8'));
}

async function atomicWrite(path, value) {
  await mkdir(dirname(path), { recursive: true, mode: 0o700 });
  const temporary = `${path}.tmp-${process.pid}`;
  await writeFile(temporary, `${JSON.stringify(value, null, 2)}\n`, { mode: 0o600 });
  await rename(temporary, path);
}

async function detectHardware() {
  return detectMacHardware({ modelIdentifier: String(flags.model || ''), allowSystemProfiler: !flags.model });
}

async function detectDisplays() {
  if (flags.snapshot) return JSON.parse(await readFile(resolve(flags.snapshot), 'utf8'));
  try {
    const { stdout } = await execFileAsync('yabai', ['-m', 'query', '--displays'], { timeout: 5000, maxBuffer: 1_000_000 });
    return { unavailable: false, displays: JSON.parse(stdout) };
  } catch (error) {
    return { unavailable: true, displays: [], message: `display discovery failed: ${error.message}` };
  }
}

function assignmentForSetup(config, hardwareProfileId, setupId, displays) {
  const requirements = config.hardwareProfiles[hardwareProfileId].setups[setupId].match.displays;
  const used = new Set();
  const bindings = {};
  for (const requirement of requirements) {
    const index = displays.findIndex((display, candidate) => !used.has(candidate)
      && (!requirement.kind || display.kind === requirement.kind)
      && (!requirement.orientation || display.orientation === requirement.orientation)
      && (!requirement.role || !display.role || display.role === requirement.role));
    if (index < 0) throw new Error(`could not bind display role “${requirement.role || 'unnamed'}”`);
    used.add(index);
    if (requirement.role) bindings[requirement.role] = displays[index].uuid;
  }
  return bindings;
}

async function inspect() {
  if (!existsSync(configFile)) throw new Error(`v3 configuration not found at ${configFile}`);
  const [config, machine, hardware, snapshot] = await Promise.all([
    readJson(configFile, null),
    readJson(machineFile, { version: 2, displayBindings: {}, displayKinds: {}, topologySelections: {} }),
    detectHardware(),
    detectDisplays()
  ]);
  const validation = validateV3(config);
  if (!validation.valid) throw new Error(`configuration is invalid:\n${validation.errors.join('\n')}`);
  const selectedHardware = selectHardwareProfile(config, machine, hardware);
  const displays = describeDisplays(snapshot, machine);
  const key = topologyKey(displays);
  const setupCandidates = selectedHardware.id ? matchingSetups(config, selectedHardware.id, snapshot, machine) : [];
  return {
    config,
    machine,
    hardware,
    snapshot,
    displays,
    topologyKey: key,
    selectedHardware,
    setupCandidates,
    confirmedSetup: machine.topologySelections?.[key] || null
  };
}

function print(value) { process.stdout.write(`${JSON.stringify(value, null, 2)}\n`); }

async function compileActive(config, machine, hardware, snapshot) {
  const source = await readFile(configFile, 'utf8');
  const runtime = generationDocument(config, { machine, hardware, snapshot }, source);
  await atomicWrite(runtimeFile, runtime);
  return runtime;
}

try {
  const value = await inspect();
  if (command === 'detect' || command === 'status') {
    const confirmedSetup = value.machine.topologySelections?.[value.topologyKey] || null;
    const setup = confirmedSetup ? value.config.hardwareProfiles?.[value.selectedHardware.id]?.setups?.[confirmedSetup] : null;
    const bindingStatus = confirmedSetup && value.selectedHardware.id
      ? setupBindingStatus(value.config, value.selectedHardware.id, confirmedSetup, value.snapshot, value.machine)
      : { ready: false, missingRoles: [] };
    print({
      mutates: false,
      hardware: value.hardware,
      hardwareSelection: value.selectedHardware,
      topologyKey: value.topologyKey,
      displays: value.displays,
      setupCandidates: value.setupCandidates,
      confirmedSetup,
      activeSetup: value.machine.activeSetup || null,
      compatibilityMode: setup?.compatibilityMode || null,
      workspaceConfigurations: setup?.workspaceConfigurations || {},
      bindingStatus,
      ready: Boolean(value.machine.hardwareProfileConfirmed && confirmedSetup && value.setupCandidates.includes(confirmedSetup) && bindingStatus.ready)
    });
  } else if (command === 'confirm') {
    const hardwareProfileId = positional[0] || value.selectedHardware.id;
    const setupId = positional[1] || (value.setupCandidates.length === 1 ? value.setupCandidates[0] : null);
    if (!hardwareProfileId || !value.config.hardwareProfiles[hardwareProfileId]) throw new Error('confirm requires a valid hardware profile id');
    const candidates = matchingSetups(value.config, hardwareProfileId, value.snapshot, value.machine);
    if (!setupId || !candidates.includes(setupId)) throw new Error(`confirm requires one matching setup id; candidates: ${candidates.join(', ') || 'none'}`);
    const displayBindings = { ...(value.machine.displayBindings || {}), ...assignmentForSetup(value.config, hardwareProfileId, setupId, value.displays) };
    const next = {
      ...value.machine,
      version: 2,
      hardwareProfile: hardwareProfileId,
      hardwareProfileConfirmed: true,
      detectedHardware: value.hardware,
      displayBindings,
      displayKinds: value.machine.displayKinds || {},
      topologySelections: { ...(value.machine.topologySelections || {}), [value.topologyKey]: setupId },
      activeSetup: setupId
    };
    const runtime = await withConfigurationWrite(dirname(configFile), async () => {
      const currentSource = JSON.parse(await readFile(configFile, 'utf8'));
      if (JSON.stringify(currentSource) !== JSON.stringify(value.config)) throw new Error('configuration changed during setup activation');
      await atomicWrite(machineFile, next);
      return compileActive(value.config, next, value.hardware, value.snapshot);
    });
    print({ confirmed: true, path: machineFile, runtimePath: runtimeFile, hardwareProfile: hardwareProfileId, setup: setupId, compatibilityMode: runtime.modes[`work_${value.config.hardwareProfiles[hardwareProfileId].setups[setupId].compatibilityMode}`].display_mode, topologyKey: value.topologyKey, displayBindings });
  } else if (command === 'activate') {
    const hardwareProfileId = value.machine.hardwareProfile;
    const setupId = value.machine.topologySelections?.[value.topologyKey];
    if (!value.machine.hardwareProfileConfirmed || !hardwareProfileId) throw new Error('hardware profile has not been confirmed; run “spacewright setup confirm”');
    if (!setupId || !value.setupCandidates.includes(setupId)) throw new Error(`current topology “${value.topologyKey}” has not been confirmed; run “spacewright setup confirm”`);
    const bindingStatus = setupBindingStatus(value.config, hardwareProfileId, setupId, value.snapshot, value.machine);
    if (!bindingStatus.ready) throw new Error(`current display roles require confirmation: ${bindingStatus.missingRoles.join(', ')}`);
    const next = { ...value.machine, activeSetup: setupId };
    const runtime = await withConfigurationWrite(dirname(configFile), async () => {
      const currentSource = JSON.parse(await readFile(configFile, 'utf8'));
      if (JSON.stringify(currentSource) !== JSON.stringify(value.config)) throw new Error('configuration changed during setup activation');
      await atomicWrite(machineFile, next);
      return compileActive(value.config, next, value.hardware, value.snapshot);
    });
    print({ activated: true, hardwareProfile: hardwareProfileId, setup: setupId, compatibilityMode: value.config.hardwareProfiles[hardwareProfileId].setups[setupId].compatibilityMode, runtimePath: runtimeFile, sourceVersion: runtime.source_version });
  } else {
    throw new Error('usage: setup-cli.mjs <detect|status|confirm|activate> [hardware-profile] [setup] [--config=path] [--snapshot=path] [--model=id]');
  }
} catch (error) {
  process.stderr.write(`${error.message}\n`);
  process.exitCode = 1;
}
