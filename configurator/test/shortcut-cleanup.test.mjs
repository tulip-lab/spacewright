import test from 'node:test';
import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

function cleanup(scenario = 'normal') {
  return execFileSync('fish', ['--no-config', 'tests/shortcut-cleanup.fish', scenario], {
    cwd: new URL('../..', import.meta.url), encoding: 'utf8'
  });
}

test('shortcut cleanup removes empty managed and unlabeled Spaces by UUID despite renumbering', () => {
  const output = cleanup();
  assert.match(output, /status=0/);
  assert.match(output, /\["HOME","TARGET","CUSTOM","ONLY"\]/);
  assert.equal((output.match(/DESTROY=/g) || []).length, 3);
  assert.doesNotMatch(output, /FOCUS=/);
});

test('dry-run and disabled cleanup never mutate', () => {
  for (const scenario of ['dry_run', 'disabled']) {
    const output = cleanup(scenario);
    assert.match(output, /status=0/);
    assert.doesNotMatch(output, /DESTROY=|FOCUS=/);
    assert.match(output, /"EMPTY","BLANK","CUSTOM","ONLY","EXTRA"/);
  }
});

test('hidden nonmovable real windows protect a Space; sticky windows do not occupy it', () => {
  assert.match(cleanup('occupied'), /\["HOME","TARGET","EMPTY","CUSTOM","ONLY"\]/);
  assert.match(cleanup('sticky'), /\["HOME","TARGET","CUSTOM","ONLY"\]/);
});

test('a Space that becomes occupied or changes label before deletion is retained', () => {
  for (const scenario of ['became_occupied', 'renamed']) assert.match(cleanup(scenario), /"EMPTY"/);
});

test('incomplete discovery and failed or ineffective destruction cannot report success', () => {
  for (const scenario of ['discovery_failed', 'destruction_failed', 'ineffective']) {
    const output = cleanup(scenario);
    assert.match(output, /status=1/);
    assert.doesNotMatch(output, /DESTROY=/);
  }
});

test('a later blank Space is removed when the primary lane has no leading Home', () => {
  const output = cleanup('no_home');
  assert.match(output, /status=0/);
  assert.match(output, /\["TARGET","CUSTOM","ONLY"\]/);
});

test('workspace shortcut no-op preserves target-only scope even when a global cleanup hook exists', () => {
  for (const failure of [false, true]) {
    const root = mkdtempSync(join(tmpdir(), 'spacewright-shortcut-test-'));
    try {
      for (const dir of ['conf.d', 'lib/spacewright/common', 'bin']) mkdirSync(join(root, dir), { recursive: true });
      writeFileSync(join(root, 'conf.d/spacewright.fish'), 'set -gx SPACEWRIGHT_ROOT "$SPACEWRIGHT_TRANSITION_PACKAGE_ROOT/lib/spacewright"\nfunction workspace_run_step; $argv[2..]; end\n');
      writeFileSync(join(root, 'bin/spacewright'), '#!/bin/sh\nprintf \'{"noop":true}\\nSPACEWRIGHT_VERIFIED\\n\'\n', { mode: 0o755 });
      writeFileSync(join(root, 'bin/yabai'), '#!/bin/sh\nexit 1\n', { mode: 0o755 });
      writeFileSync(join(root, 'lib/spacewright/common/workspace_cleanup_after_shortcut.fish'),
        'function workspace_cleanup_after_shortcut\n echo CLEANUP_RAN\n return ' + (failure ? '7' : '0') + '\nend\n');
      const args = ['configurator/mode-transition.mjs', 'workspace', 'gtd_chat', 'tall',
        '--package-root=' + root, '--state-root=' + join(root, 'state'), '--config-root=' + join(root, 'config')];
      const options = { encoding: 'utf8', env: { ...process.env, PATH: join(root, 'bin') + ':' + process.env.PATH, SPACEWRIGHT_BANNER_DISABLE: '1' } };
      assert.doesNotMatch(execFileSync(process.execPath, args, options), /CLEANUP_RAN/);
      const status = JSON.parse(readFileSync(join(root, 'state/mode-transition/status.json'), 'utf8'));
      assert.equal(status.status, 'completed');
    } finally {
      rmSync(root, { recursive: true, force: true });
    }
  }
});
