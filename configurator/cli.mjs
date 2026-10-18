#!/usr/bin/env node

import { readFile } from 'node:fs/promises';
import { existsSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { basename, dirname, join, resolve } from 'node:path';
import { execFile, spawn } from 'node:child_process';
import { promisify } from 'node:util';
import { CONFIG_COMPILER_VERSION, compileSkhd, compileV2, migrateV1, starterConfig, validateV2 } from './lib/config-v2.mjs';
import { compileSkhdV3, compileV3, migrateV2ToV3, resolveV3, starterV3, validateV3 } from './lib/config-v3.mjs';
import { atomicText, generationDocument, stableRead, withConfigurationWrite } from './lib/config-store.mjs';
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

async function resolutionContext(config, machineOverride) {
  const stateRoot = resolve(flags['state-root'] || process.env.SPACEWRIGHT_STATE_ROOT || join(process.env.HOME, '.local', 'state', 'spacewright'));
  const machinePath = resolve(flags.machine || join(stateRoot, 'machine.json'));
  const machine = machineOverride ?? (existsSync(machinePath) ? JSON.parse(await readFile(machinePath, 'utf8')) : { version: 2, displayBindings: {}, displayKinds: {}, topologySelections: {} });
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
  return generationDocument(config, config.version === 3 ? await resolutionContext(config) : null, source);
}

function validateCompileOptions() {
  const valued = ['state-root', 'machine', 'model', 'snapshot', 'setup'];
  for (const [key, value] of Object.entries(flags)) {
    if (key === 'dry-run' && command === 'compile-to' && value === true) continue;
    if (key === 'repair-incomplete-save' && command === 'compile-to' && value === true) continue;
    if (!valued.includes(key)) throw new Error(`unknown option or invalid flag: --${key}`);
    if (value === true || !value) throw new Error(`--${key} requires a value (--${key}=value)`);
  }
  const positional = process.argv.slice(3).filter(value => !value.startsWith('--'));
  if (positional.length !== (['compile-to', 'diff'].includes(command) ? 2 : 1)) throw new Error(`${command} requires input${['compile-to', 'diff'].includes(command) ? ' and output' : ''} paths`);
}

async function readCompiledDocument({ownedWrite = false} = {}) {
  const stateRoot = resolve(flags['state-root'] || process.env.SPACEWRIGHT_STATE_ROOT || join(process.env.HOME, '.local', 'state', 'spacewright'));
  const machinePath = flags.machine || join(stateRoot, 'machine.json');
  const activePath = () => join(dirname(resolve(file)), existsSync(join(dirname(resolve(file)), 'config.v3.json')) ? 'config.v3.json' : 'config.v2.json');
  const selected = activePath();
  const namedVersion = {'config.v2.json':2, 'config.v3.json':3}[basename(file)];
  if (namedVersion && ['compile-to', 'diff'].includes(command) && selected !== resolve(file)) throw new Error('active configuration changed before compilation');
  const loaded = await stableRead(file, machinePath, {ownedWrite});
  if (namedVersion && loaded.config.version !== namedVersion) throw new Error('active configuration version does not match its filename');
  const resolution = loaded.config.version === 3 ? await resolutionContext(loaded.config, loaded.machine) : null;
  const document = generationDocument(loaded.config, resolution, loaded.source);
  const after = await stableRead(file, machinePath, {ownedWrite});
  if (selected !== activePath() || after.source !== loaded.source || JSON.stringify(after.machine) !== JSON.stringify(loaded.machine)) throw new Error('configuration generation changed during compilation');
  return document;
}

async function diffDocument(output, document) {
  // Feed the read-only candidate over stdin: no configuration guard or temporary
  // candidate survives errors, cancellation, or an unavailable runtime file.
  const child = spawn('diff', ['-u', output, '-'], {stdio: ['pipe', 'inherit', 'inherit']});
  const code = await new Promise((resolve, reject) => {
    child.once('error', reject); child.once('close', resolve);
    child.stdin.on('error', error => { if (error.code !== 'EPIPE') { child.kill(); reject(error); } });
    child.stdin.end(`${JSON.stringify(document, null, 2)}\n`);
  });
  if (code === 0) process.stdout.write('runtime is current\n');
  // Preserve the public config-diff contract: differences are a successful
  // inspection; compilation and comparison failures are errors.
  else if (code !== 1) throw new Error(`runtime comparison failed (exit ${code})`);
}

try {
  if (['compile', 'effective', 'compile-to', 'diff'].includes(command)) validateCompileOptions();
  if (command === 'starter') process.stdout.write(`${JSON.stringify(starterConfig(), null, 2)}\n`);
  else if (command === 'starter-v3') process.stdout.write(`${JSON.stringify(starterV3(), null, 2)}\n`);
  else if (command === 'validate') {
    const result = validateConfig(await load(file));
    if (!result.valid) {
      process.stderr.write(`${result.errors.join('\n')}\n`);
      process.exitCode = 1;
    }
  } else if (command === 'compile' || command === 'effective') {
    const candidate = await readCompiledDocument();
    if (command === 'effective') delete candidate.generated;
    process.stdout.write(`${JSON.stringify(candidate, null, 2)}\n`);
  }
  else if (command === 'compile-to') {
    const output = process.argv[4];
    if (!file || !output) throw new Error('compile-to requires input and output paths');
    if (flags['dry-run']) {
      await readCompiledDocument();
      process.stdout.write(`dry_run=true\nmutates=false\nruntime_path=${resolve(output)}\n`);
    } else {
      await withConfigurationWrite(dirname(resolve(file)), async transaction => {
        const document = await readCompiledDocument({ownedWrite:true});
        transaction.beginWrite();
        await atomicText(output, `${JSON.stringify(document,null,2)}\n`);
      }, {repair:flags['repair-incomplete-save'] === true, trackWrites:true});
    }
  }
  else if (command === 'diff') await diffDocument(process.argv[4], await readCompiledDocument());
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
