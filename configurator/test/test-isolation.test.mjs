import test from 'node:test';
import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
test('a Fish child without inherited function mocks blocks PATH and absolute desktop commands', () => {
  const code = 'function yabai; echo parent-mock; end; fish --no-config -c "command yabai -m space --destroy; echo blocked=\\$status; /usr/bin/open -a Finder; echo absolute=\\$status"';
  const output = execFileSync(process.execPath, ['scripts/isolated-check.mjs', 'fish', '--no-config', '-c', code], { encoding: 'utf8' });
  assert.match(output, /blocked=97/);
  assert.match(output, /absolute=[1-9][0-9]*/);
  assert.doesNotMatch(output, /parent-mock/);
});
