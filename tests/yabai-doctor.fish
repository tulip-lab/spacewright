#!/usr/bin/env fish

set -l test_file (path resolve (status filename))
set -l package_root (path dirname (path dirname $test_file))
source "$package_root/lib/spacewright/common/yabai_doctor.fish"

function __yabai_doctor_binary_path
    echo /opt/homebrew/bin/yabai
end
function __yabai_doctor_real_path
    echo /opt/homebrew/bin/yabai-compatible
end
function __yabai_doctor_sha256
    echo abc123
end
function __yabai_doctor_version
    echo yabai-v7.1.25
end
function __yabai_doctor_loaded_service
    echo gui/501/com.asmvik.yabai
end
function __yabai_doctor_service_running
    return 0
end
function __yabai_doctor_queries
    printf '%s\n' displays=1 spaces=8 windows=12
end
function __yabai_doctor_sudo_rule_matches
    return 0
end
function __yabai_doctor_macos_version
    echo 27.2
end

set -l output (__yabai_doctor_check)
test $status -eq 0
or exit 1
string match -q '*macOS 27+ Space support cannot be inferred*' -- $output
or exit 2

set output (__yabai_doctor_ensure_head)
test $status -eq 0
or exit 3
string match -q '*preserve current yabai build*' -- $output
or exit 4

function __yabai_doctor_binary_path
    return 1
end
set output (__yabai_doctor_ensure_head 2>&1)
test $status -eq 1
or exit 9
string match -q '*install a macOS 27-compatible yabai build*' -- $output
or exit 10
function __yabai_doctor_binary_path
    echo /opt/homebrew/bin/yabai
end

function __yabai_doctor_macos_version
    echo 26.6
end
set output (__yabai_doctor_check)
test $status -eq 1
or exit 5
string match -q '*requires the yabai HEAD Space fix*' -- $output
or exit 6

function __yabai_doctor_real_path
    echo /opt/homebrew/Cellar/yabai/HEAD-test/bin/yabai
end
set output (__yabai_doctor_check)
test $status -eq 0
or exit 7
string match -q '*HEAD build active*' -- $output
or exit 8

echo 'OK      yabai doctor recognizes macOS 27 custom builds and macOS 26.6 HEAD'
