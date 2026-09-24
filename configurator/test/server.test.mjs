import test from 'node:test';
import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { mkdtemp, readFile, rm, access, readdir } from 'node:fs/promises';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import { starterConfig } from '../lib/config-v2.mjs';

const packageRoot = new URL('../..', import.meta.url).pathname;

async function startServer(configRoot, stateRoot) {
  const token = 'integration-test-token';
  const child = spawn(process.execPath, [
    join(packageRoot, 'configurator/server.mjs'),
    `--package-root=${packageRoot}`,
    `--config-root=${configRoot}`,
    `--state-root=${stateRoot}`,
    `--token=${token}`,
    '--port=0',
    '--no-open'
  ], { stdio: ['ignore', 'pipe', 'pipe'] });
  const url = await new Promise((resolve, reject) => {
    let output = '';
    const timer = setTimeout(() => reject(new Error(`server did not start: ${output}`)), 5000);
    child.once('error', reject);
    child.stderr.on('data', (chunk) => { output += chunk; });
    child.stdout.on('data', (chunk) => {
      output += chunk;
      const match = output.match(/SPACEWRIGHT_CONFIGURATOR_URL=(http:\/\/[^?\s]+)/);
      if (match) { clearTimeout(timer); resolve(match[1]); }
    });
  });
  return { child, token, url };
}

async function json(url, path, options = {}) {
  const response = await fetch(new URL(path.slice(1), url), options);
  return { status: response.status, body: await response.json() };
}

test('local server isolates machine bindings and generated skhd output', async (context) => {
  const root = await mkdtemp(join(tmpdir(), 'spacewright-server-test-'));
  const configRoot = join(root, 'config');
  const stateRoot = join(root, 'state');
  const { child, token, url } = await startServer(configRoot, stateRoot);
  context.after(async () => {
    child.kill('SIGTERM');
    await rm(root, { recursive: true, force: true });
  });

  const initial = await json(url, '/api/machine');
  assert.equal(initial.status, 200);
  assert.deepEqual(initial.body.machine, { version: 1, displayBindings: {} });

  const legacy = await json(url, '/api/legacy-preview');
  assert.equal(legacy.status, 200);
  assert.equal(legacy.body.config.version, 2);
  assert.equal(legacy.body.source, 'legacy-preview');
  assert.equal(legacy.body.writes, false);

  const unauthorized = await json(url, '/api/display-bindings', {
    method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ displayBindings: {} })
  });
  assert.equal(unauthorized.status, 403);

  const invalid = await json(url, '/api/display-bindings', {
    method: 'POST', headers: { 'content-type': 'application/json', 'x-spacewright-token': token }, body: JSON.stringify({ displayBindings: { missing: 'DISPLAY-1234' } })
  });
  assert.equal(invalid.status, 422);

  const saved = await json(url, '/api/display-bindings', {
    method: 'POST', headers: { 'content-type': 'application/json', 'x-spacewright-token': token }, body: JSON.stringify({ displayBindings: { primary: 'DISPLAY-1234' } })
  });
  assert.equal(saved.status, 200);
  assert.deepEqual(JSON.parse(await readFile(join(stateRoot, 'machine.json'), 'utf8')), { version: 1, displayBindings: { primary: 'DISPLAY-1234' } });

  const candidate = starterConfig();
  candidate.displayRoles.studio = { name: 'Studio display', portableMatch: { orientation: 'wide' } };
  const candidateBinding = await json(url, '/api/display-bindings', {
    method: 'POST', headers: { 'content-type': 'application/json', 'x-spacewright-token': token }, body: JSON.stringify({ displayBindings: { studio: 'DISPLAY-5678' }, config: candidate })
  });
  assert.equal(candidateBinding.status, 200);
  const duplicateBinding = await json(url, '/api/display-bindings', {
    method: 'POST', headers: { 'content-type': 'application/json', 'x-spacewright-token': token }, body: JSON.stringify({ displayBindings: { primary: 'DISPLAY-9999', task: 'DISPLAY-9999' }, config: candidate })
  });
  assert.equal(duplicateBinding.status, 422);

  const generated = await json(url, '/api/skhd', {
    method: 'POST', headers: { 'content-type': 'application/json', 'x-spacewright-token': token }, body: JSON.stringify(starterConfig())
  });
  assert.equal(generated.status, 200);
  assert.equal(generated.body.path, join(configRoot, 'generated', 'spacewright.skhdrc'));
  assert.match(await readFile(generated.body.path, 'utf8'), /work_wide/);

  const first = starterConfig();
  const savedConfig = await json(url, '/api/save', {
    method: 'POST', headers: { 'content-type': 'application/json', 'x-spacewright-token': token }, body: JSON.stringify(first)
  });
  assert.equal(savedConfig.status, 200);
  assert.equal(savedConfig.body.verified, true);
  await access(join(configRoot, 'generated', 'runtime.json'));
  const runtime = JSON.parse(await readFile(join(configRoot, 'generated', 'runtime.json'), 'utf8'));
  assert.match(runtime.generated.source_sha256, /^[a-f0-9]{64}$/);

  const second = starterConfig();
  second.metadata.name = 'Second version';
  assert.equal((await json(url, '/api/save', {
    method: 'POST', headers: { 'content-type': 'application/json', 'x-spacewright-token': token }, body: JSON.stringify(second)
  })).status, 200);
  assert.equal((await readdir(join(configRoot, 'backups'))).length, 1);
  const restored = await json(url, '/api/restore-backup', {
    method: 'POST', headers: { 'content-type': 'application/json', 'x-spacewright-token': token }
  });
  assert.equal(restored.status, 200);
  assert.equal(restored.body.config.metadata.name, first.metadata.name);

  const snapshots = await json(url, '/api/history');
  assert.equal(snapshots.status, 200);
  assert.ok(snapshots.body.snapshots.length >= 2);
  const preview = await json(url, '/api/preview', {
    method: 'POST', headers: { 'content-type': 'application/json', 'x-spacewright-token': token }, body: JSON.stringify({ config: second, mode: 'wide' })
  });
  assert.equal(preview.status, 200);
  assert.equal(preview.body.dryRun, true);
  assert.equal(preview.body.mutates, false);
  const diagnostics = await json(url, '/api/diagnostics');
  assert.equal(diagnostics.status, 200);
  assert.ok(diagnostics.body.checks.some((check) => check.id === 'schema' && check.ok));
  const imported = await json(url, '/api/import', {
    method: 'POST', headers: { 'content-type': 'application/json', 'x-spacewright-token': token }, body: JSON.stringify({ text: `version: 2\nmetadata:\n  name: invalid minimal\n` })
  });
  assert.equal(imported.status, 422);
  const tasks = await json(url, '/api/tasks');
  assert.equal(tasks.status, 200);
  assert.deepEqual(tasks.body.tasks, []);
  const unconfirmedExecution = await json(url, '/api/execute', {
    method: 'POST', headers: { 'content-type': 'application/json', 'x-spacewright-token': token }, body: JSON.stringify({ kind: 'mode', target: 'wide' })
  });
  assert.equal(unconfirmedExecution.status, 422);
  const invalidExecution = await json(url, '/api/execute', {
    method: 'POST', headers: { 'content-type': 'application/json', 'x-spacewright-token': token }, body: JSON.stringify({ kind: 'mode', target: 'unknown', confirmed: true })
  });
  assert.equal(invalidExecution.status, 422);
  const evaluatedRules = await json(url, '/api/rules/evaluate', {
    method: 'POST', headers: { 'content-type': 'application/json', 'x-spacewright-token': token }, body: JSON.stringify({ event: 'manual', execute: false })
  });
  assert.equal(evaluatedRules.status, 200);
  assert.equal(evaluatedRules.body.mutates, false);
});
