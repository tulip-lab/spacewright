#!/usr/bin/env node

import { readFile, writeFile, rename, mkdir } from 'node:fs/promises';
import { existsSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { dirname, join, resolve } from 'node:path';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { CONFIG_COMPILER_VERSION, compileSkhd, compileV2, migrateV1, starterConfig, validateV2 } from './lib/config-v2.mjs';
import { compileSkhdV3, compileV3, migrateV2ToV3, resolveV3, starterV3, validateV3 } from './lib/config-v3.mjs';
import { detectMacHardware } from './lib/hardware-detection.mjs';

const execFileAsync = promisify(execFile);
const [command, file] = process.argv.slice(2);
const flags = Object.fromEntries(process.argv.slice(2).filter((value) => value.startsWith('--')).map((value) => {
  const [key, ...rest] = value.slice(2).split('=');
  return [key, rest.length ? rest.join('=') : true];
}));

async function load(path) {
  if (!path || path === '-') {
    let input = '';
    for await (const chunk of process.stdin) input += chunk;
    return JSON.parse(input);
  }
  return JSON.parse(await readFile(path, 'utf8'));
}

async function resolutionContext(config) {
  const stateRoot = resolve(flags['state-root'] || process.env.SPACEWRIGHT_STATE_ROOT || join(process.env.HOME, '.local', 'state', 'spacewright'));
  const machinePath = resolve(flags.machine || join(stateRoot, 'machine.json'));
  const machine = existsSync(machinePath) ? JSON.parse(await readFile(machinePath, 'utf8')) : { version: 2, displayBindings: {}, displayKinds: {}, topologySelections: {} };
  const hardware = await detectMacHardware({ modelIdentifier: String(flags.model || ''), allowSystemProfiler: !flags.model });
  let snapshot;
  if (flags.snapshot) snapshot = JSON.parse(await readFile(resolve(flags.snapshot), 'utf8'));
  else {
    try { snapshot = { unavailable: false, displays: JSON.parse((await execFileAsync('yabai', ['-m', 'query', '--displays'], { timeout: 5000, maxBuffer: 1_000_000 })).stdout) }; }
    catch (error) { snapshot = { unavailable: true, displays: [], message: `display discovery failed: ${error.message}` }; }
  }
  return { machine, hardware, snapshot, setupId: flags.setup || null };
}

async function compileConfig(config) {
  if (config.version === 2) return compileV2(config);
  if (config.version === 3) return compileV3(config, await resolutionContext(config));
  throw new Error('configuration version must be 2 or 3');
}

function validateConfig(config) {
  return config?.version === 3 ? validateV3(config) : validateV2(config);
}

async function compiledDocument(config, source = `${JSON.stringify(config, null, 2)}\n`) {
  const sourceSha256 = createHash('sha256').update(source).digest('hex');
  return { ...await compileConfig(config), generated: { format_version: 1, compiler_version: CONFIG_COMPILER_VERSION, source_version: config.version, generation_id: sourceSha256.slice(0, 16), source_sha256: sourceSha256 } };
}

async function writeAtomic(path, value) {
  await mkdir(dirname(path), { recursive: true, mode: 0o700 });
  const temporary = `${path}.tmp-${process.pid}`;
  await writeFile(temporary, value, { mode: 0o600 });
  await rename(temporary, path);
}

try {
  if (command === 'starter') process.stdout.write(`${JSON.stringify(starterConfig(), null, 2)}\n`);
  else if (command === 'starter-v3') process.stdout.write(`${JSON.stringify(starterV3(), null, 2)}\n`);
  else if (command === 'validate') {
    const result = validateConfig(await load(file));
    if (!result.valid) {
      process.stderr.write(`${result.errors.join('\n')}\n`);
      process.exitCode = 1;
    }
  } else if (command === 'compile') process.stdout.write(`${JSON.stringify(await compileConfig(await load(file)), null, 2)}\n`);
  else if (command === 'compile-to') {
    const output = process.argv[4];
    if (!file || !output) throw new Error('compile-to requires input and output paths');
    const source = await readFile(file, 'utf8');
    await writeAtomic(output, `${JSON.stringify(await compiledDocument(JSON.parse(source), source), null, 2)}\n`);
  }
  else if (command === 'migrate-v1') process.stdout.write(`${JSON.stringify(migrateV1(await load(file)), null, 2)}\n`);
  else if (command === 'migrate-v2') process.stdout.write(`${JSON.stringify(migrateV2ToV3(await load(file)), null, 2)}\n`);
  else if (command === 'skhd') {
    const config = await load(file);
    process.stdout.write(config.version === 3 ? compileSkhdV3(config, await resolutionContext(config)) : compileSkhd(config));
  }
  else {
    process.stderr.write('usage: cli.mjs <starter|starter-v3|validate|compile|compile-to|migrate-v1|migrate-v2|skhd> [file|-] [output]\n');
    process.exitCode = 2;
  }
} catch (error) {
  process.stderr.write(`${error.message}\n`);
  process.exitCode = 1;
}
