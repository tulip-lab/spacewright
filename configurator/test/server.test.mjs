import test from 'node:test';
import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { mkdtemp, readFile, rm, access, readdir, writeFile } from 'node:fs/promises';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import { starterConfig } from '../lib/config-v2.mjs';
import { writeTransitionRecord } from '../lib/transition-history.mjs';

const packageRoot = new URL('../..', import.meta.url).pathname;

async function startServer(configRoot, stateRoot, skhdFile) {
  const token = 'integration-test-token';
  const child = spawn(process.execPath, [
    join(packageRoot, 'configurator/server.mjs'),
    `--package-root=${packageRoot}`,
    `--config-root=${configRoot}`,
    `--state-root=${stateRoot}`,
    `--skhd-file=${skhdFile}`,
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
  const skhdFile = join(root, 'skhdrc');
  await writeFile(skhdFile, [
    "fn + shift - 0 : fish -lc 'display_apply_solo; work_solo'",
    "alt + shift - 1 : fish -lc 'coding_wide'",
    "ctrl + shift - 2 : fish -lc 'coding_family_tall'",
    "fn + shift - 9 : fish -lc 'spacewright workspace gtd_ai solo'",
    "cmd - x : open -a Example"
  ].join('\n'));
  await writeTransitionRecord(stateRoot, {
    schemaVersion: 1, runId: '1700000000000-123-abcdef12', mode: 'solo', scope: 'workspace', workspace: 'gtd_ai',
    targetKey: 'workspace:gtd_ai:solo', targetLabel: 'GTD AI · solo', status: 'completed', phase: 'GTD AI · solo is ready', step: 2,
    startedAt: '2026-10-06T00:00:00.000Z', finishedAt: '2026-10-06T00:00:02.000Z', durationMs: 2000,
    warnings: ['optional ChatGPT missing'], skipped: ['skipping ChatGPT'], errors: [], logTail: ['OUT complete']
  });
  const { child, token, url } = await startServer(configRoot, stateRoot, skhdFile);
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
  assert.match(await readFile(generated.body.path, 'utf8'), /spacewright mode wide/);
  const shortcutInventory = await json(url, '/api/shortcuts');
  assert.equal(shortcutInventory.status, 200);
  assert.equal(shortcutInventory.body.mutates, false);
  assert.ok(shortcutInventory.body.bindings.some((binding) => binding.action.type === 'activateMode' && binding.action.mode === 'wide'));
  assert.ok(shortcutInventory.body.bindings.some((binding) => binding.action.type === 'activateMode' && binding.action.mode === 'solo' && binding.keys.key === '0'));
  assert.ok(shortcutInventory.body.bindings.some((binding) => binding.action.type === 'activateWorkspace' && binding.action.workspace === 'coding' && binding.action.mode === 'wide'));
  assert.ok(shortcutInventory.body.bindings.some((binding) => binding.action.type === 'activateWorkspace' && binding.action.workspace === 'gtd_ai' && binding.action.mode === 'solo'));
  assert.ok(shortcutInventory.body.bindings.some((binding) => binding.action.type === 'externalCommand' && binding.action.command === 'coding_family_tall'));
  assert.equal(shortcutInventory.body.bindings.some((binding) => binding.keys.key === 'x'), false);

  const first = starterConfig();
  const initialConfig = await json(url, '/api/config');
  assert.equal(initialConfig.status, 200);
  assert.match(initialConfig.body.revision, /^[a-f0-9]{64}$/);
  assert.equal((await json(url, '/api/config')).body.revision, initialConfig.body.revision);
  const savedConfig = await json(url, '/api/save', {
    method: 'POST', headers: { 'content-type': 'application/json', 'x-spacewright-token': token }, body: JSON.stringify({ config: first, baseRevision: initialConfig.body.revision })
  });
  assert.equal(savedConfig.status, 200, JSON.stringify(savedConfig.body));
  assert.equal(savedConfig.body.verified, true);
  await access(join(configRoot, 'generated', 'runtime.json'));
  const runtime = JSON.parse(await readFile(join(configRoot, 'generated', 'runtime.json'), 'utf8'));
  assert.match(runtime.generated.source_sha256, /^[a-f0-9]{64}$/);

  const second = starterConfig();
  second.metadata.name = 'Second version';
  const secondSave = await json(url, '/api/save', {
    method: 'POST', headers: { 'content-type': 'application/json', 'x-spacewright-token': token }, body: JSON.stringify({ config: second, baseRevision: savedConfig.body.revision })
  });
  assert.equal(secondSave.status, 200);
  const staleSave = await json(url, '/api/save', {
    method: 'POST', headers: { 'content-type': 'application/json', 'x-spacewright-token': token }, body: JSON.stringify({ config: first, baseRevision: savedConfig.body.revision })
  });
  assert.equal(staleSave.status, 409);
  assert.equal(staleSave.body.code, 'configuration_conflict');
  assert.equal((await readdir(join(configRoot, 'backups'))).length, 1);
  const restored = await json(url, '/api/restore-backup', {
    method: 'POST', headers: { 'content-type': 'application/json', 'x-spacewright-token': token }
  });
  assert.equal(restored.status, 200);
  assert.equal(restored.body.config.metadata.name, first.metadata.name);

  const concurrentA = structuredClone(first); concurrentA.metadata.name = 'Concurrent A';
  const concurrentB = structuredClone(first); concurrentB.metadata.name = 'Concurrent B';
  const concurrentSaves = await Promise.all([concurrentA, concurrentB].map((config) => json(url, '/api/save', {
    method: 'POST', headers: { 'content-type': 'application/json', 'x-spacewright-token': token }, body: JSON.stringify({ config, baseRevision: restored.body.revision })
  })));
  assert.deepEqual(concurrentSaves.map((result) => result.status).sort(), [200, 409]);

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
  assert.equal(diagnostics.body.recentTransitions[0].workspace, 'gtd_ai');
  assert.ok(diagnostics.body.checks.some((check) => check.id === 'transition_history' && check.ok));
  const transitionHistory = await json(url, '/api/transition-history');
  assert.equal(transitionHistory.status, 200);
  assert.equal(transitionHistory.body.transitions[0].targetLabel, 'GTD AI · solo');
  const runtimePath = join(configRoot, 'generated', 'runtime.json');
  const savedRuntime = await readFile(runtimePath, 'utf8');
  await writeFile(runtimePath, '{invalid json');
  const corruptRuntimeDiagnostics = await json(url, '/api/diagnostics');
  assert.equal(corruptRuntimeDiagnostics.status, 200);
  assert.ok(corruptRuntimeDiagnostics.body.checks.some((check) => check.id === 'compiled_runtime' && !check.ok && check.detail.includes('unreadable')));
  await writeFile(runtimePath, savedRuntime);
  const imported = await json(url, '/api/import', {
    method: 'POST', headers: { 'content-type': 'application/json', 'x-spacewright-token': token }, body: JSON.stringify({ text: `version: 2\nmetadata:\n  name: invalid minimal\n` })
  });
  assert.equal(imported.status, 422);
  const tasks = await json(url, '/api/tasks');
  assert.equal(tasks.status, 200);
  assert.deepEqual(tasks.body.tasks, []);
  const clearedTransitions = await json(url, '/api/transition-history', {
    method: 'DELETE', headers: { 'content-type': 'application/json', 'x-spacewright-token': token }
  });
  assert.equal(clearedTransitions.status, 200);
  assert.deepEqual((await json(url, '/api/transition-history')).body.transitions, []);
  const unconfirmedExecution = await json(url, '/api/execute', {
    method: 'POST', headers: { 'content-type': 'application/json', 'x-spacewright-token': token }, body: JSON.stringify({ kind: 'mode', target: 'wide' })
  });
  assert.equal(unconfirmedExecution.status, 422);
  const invalidExecution = await json(url, '/api/execute', {
    method: 'POST', headers: { 'content-type': 'application/json', 'x-spacewright-token': token }, body: JSON.stringify({ kind: 'mode', target: 'unknown', confirmed: true })
  });
  assert.equal(invalidExecution.status, 428);
  assert.equal(invalidExecution.body.code, 'preview_required');
  const staleExecution = await json(url, '/api/execute', {
    method: 'POST', headers: { 'content-type': 'application/json', 'x-spacewright-token': token }, body: JSON.stringify({ kind: 'mode', target: 'wide', confirmed: true, expectedPlanId: 'stale', expectedConfigDigest: 'stale', expectedSnapshotId: 'stale' })
  });
  assert.equal(staleExecution.status, 409);
  assert.equal(staleExecution.body.code, 'plan_stale');
  const evaluatedRules = await json(url, '/api/rules/evaluate', {
    method: 'POST', headers: { 'content-type': 'application/json', 'x-spacewright-token': token }, body: JSON.stringify({ event: 'manual', execute: false, config: second })
  });
  assert.equal(evaluatedRules.status, 200);
  assert.equal(evaluatedRules.body.mutates, false);
});
