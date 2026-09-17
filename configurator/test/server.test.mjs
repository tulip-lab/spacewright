import test from 'node:test';
import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { mkdtemp, readFile, rm } from 'node:fs/promises';
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

  const generated = await json(url, '/api/skhd', {
    method: 'POST', headers: { 'content-type': 'application/json', 'x-spacewright-token': token }, body: JSON.stringify(starterConfig())
  });
  assert.equal(generated.status, 200);
  assert.equal(generated.body.path, join(configRoot, 'generated', 'spacewright.skhdrc'));
  assert.match(await readFile(generated.body.path, 'utf8'), /work_wide/);
});
