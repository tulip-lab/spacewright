#!/usr/bin/env node

import { readFile, writeFile, rename, mkdir } from 'node:fs/promises';
import { createHash } from 'node:crypto';
import { dirname } from 'node:path';
import { CONFIG_COMPILER_VERSION, compileSkhd, compileV2, migrateV1, starterConfig, validateV2 } from './lib/config-v2.mjs';

const [command, file] = process.argv.slice(2);

async function load(path) {
  if (!path || path === '-') {
    let input = '';
    for await (const chunk of process.stdin) input += chunk;
    return JSON.parse(input);
  }
  return JSON.parse(await readFile(path, 'utf8'));
}

function compiledDocument(config, source = `${JSON.stringify(config, null, 2)}\n`) {
  const sourceSha256 = createHash('sha256').update(source).digest('hex');
  return { ...compileV2(config), generated: { format_version: 1, compiler_version: CONFIG_COMPILER_VERSION, source_version: config.version, generation_id: sourceSha256.slice(0, 16), source_sha256: sourceSha256 } };
}

async function writeAtomic(path, value) {
  await mkdir(dirname(path), { recursive: true, mode: 0o700 });
  const temporary = `${path}.tmp-${process.pid}`;
  await writeFile(temporary, value, { mode: 0o600 });
  await rename(temporary, path);
}

try {
  if (command === 'starter') process.stdout.write(`${JSON.stringify(starterConfig(), null, 2)}\n`);
  else if (command === 'validate') {
    const result = validateV2(await load(file));
    if (!result.valid) {
      process.stderr.write(`${result.errors.join('\n')}\n`);
      process.exitCode = 1;
    }
  } else if (command === 'compile') process.stdout.write(`${JSON.stringify(compileV2(await load(file)), null, 2)}\n`);
  else if (command === 'compile-to') {
    const output = process.argv[4];
    if (!file || !output) throw new Error('compile-to requires input and output paths');
    const source = await readFile(file, 'utf8');
    await writeAtomic(output, `${JSON.stringify(compiledDocument(JSON.parse(source), source), null, 2)}\n`);
  }
  else if (command === 'migrate-v1') process.stdout.write(`${JSON.stringify(migrateV1(await load(file)), null, 2)}\n`);
  else if (command === 'skhd') process.stdout.write(compileSkhd(await load(file)));
  else {
    process.stderr.write('usage: cli.mjs <starter|validate|compile|compile-to|migrate-v1|skhd> [file|-] [output]\n');
    process.exitCode = 2;
  }
} catch (error) {
  process.stderr.write(`${error.message}\n`);
  process.exitCode = 1;
}
