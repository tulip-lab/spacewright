#!/usr/bin/env node

import { readFile } from 'node:fs/promises';
import { compileSkhd, compileV2, migrateV1, starterConfig, validateV2 } from './lib/config-v2.mjs';

const [command, file] = process.argv.slice(2);

async function load(path) {
  if (!path || path === '-') {
    let input = '';
    for await (const chunk of process.stdin) input += chunk;
    return JSON.parse(input);
  }
  return JSON.parse(await readFile(path, 'utf8'));
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
  else if (command === 'migrate-v1') process.stdout.write(`${JSON.stringify(migrateV1(await load(file)), null, 2)}\n`);
  else if (command === 'skhd') process.stdout.write(compileSkhd(await load(file)));
  else {
    process.stderr.write('usage: cli.mjs <starter|validate|compile|migrate-v1|skhd> [file|-]\n');
    process.exitCode = 2;
  }
} catch (error) {
  process.stderr.write(`${error.message}\n`);
  process.exitCode = 1;
}
