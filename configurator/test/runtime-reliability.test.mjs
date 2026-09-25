import test from 'node:test';
import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { resolve } from 'node:path';

const root = resolve(import.meta.dirname, '../..');

function fish(script) {
  return execFileSync('fish', ['-c', script], { cwd: root, encoding: 'utf8' }).trim();
}

test('window moves retry until every requested window is confirmed', () => {
  const output = fish(`
    source lib/spacewright/common/ws_move_windows_to_space.fish
    set -g moved
    function sleep; end
    function ws_jq; command jq $argv; end
    function ws_window; set -ga moved $argv[1]; return 0; end
    function ws_focus_space; echo focus=$argv[1]; end
    function ws_query_windows
      if test "$argv[2]" = confirm_1
        echo '[{"id":11,"space":8},{"id":12,"space":3}]'
      else
        echo '[{"id":11,"space":8},{"id":12,"space":8}]'
      end
    end
    ws_move_windows_to_space 8 11 12
    or exit 1
    echo moved=(string join , -- $moved)
  `);
  assert.match(output, /focus=8/);
  assert.match(output, /moved=11,12/);
});

test('unlabeled cleanup uses authoritative windows and keeps the last space on a display', () => {
  const output = fish(`
    source lib/spacewright/common/workspace_cleanup_spaces.fish
    set -g destroyed
    function sleep; end
    function ws_jq; command jq $argv; end
    function workspace_cleanup_query_spaces
      echo '[{"index":1,"display":1,"label":"","windows":[]},{"index":2,"display":1,"label":"","windows":[]},{"index":3,"display":1,"label":"","windows":[]},{"index":4,"display":2,"label":"","windows":[]}]'
    end
    function workspace_cleanup_query_windows
      echo '[{"id":40,"space":3,"is-sticky":false}]'
    end
    function ws_yabai
      if test "$argv[1] $argv[2] $argv[4]" = '-m space --destroy'
        set -ga destroyed $argv[3]
        return 0
      end
      return 1
    end
    cleanup_unlabeled_empty_spaces 1
    echo destroyed=(string join , -- $destroyed)
  `);
  assert.equal(output, 'destroyed=2');
});

test('generic layouts retain role alignment when a middle optional window is absent', () => {
  const output = fish(`
    source lib/spacewright/common/workspace_config_runtime.fish
    set -g grids
    function sleep; end
    function ws_jq; command jq $argv; end
    function ws_query_windows
      echo '[{"id":11,"app":"Primary","space":8,"is-minimized":false,"can-move":true},{"id":33,"app":"Third","space":8,"is-minimized":false,"can-move":true}]'
    end
    function workspace_resolve_display_role; echo 1; end
    function workspace_prepare_labeled_space; echo 8; end
    function ws_move_windows_to_space; return 0; end
    function ws_window; set -ga grids "$argv[1]:$argv[3]"; end
    set -l plan '{"id":"test_wide","label":"test_wide","display_role":"wide","space_layout":"float","windows":[{"role":"primary","app_key":"primary","app_names":["Primary"],"required":true},{"role":"helper","app_key":"helper","app_names":["Missing"],"required":false},{"role":"third","app_key":"third","app_names":["Third"],"required":false}],"layout":[{"role":"primary","grid":"A"},{"role":"helper","grid":"B"},{"role":"third","grid":"C"}]}'
    __workspace_run_configured_generic_layout "$plan" 0
    or exit 1
    echo grids=(string join , -- $grids)
  `);
  assert.equal(output, 'grids=11:A,33:C');
});
