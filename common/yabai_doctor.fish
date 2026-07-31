function yabai_doctor --description "Diagnose yabai and optionally repair its runtime setup"
    argparse h/help repair -- $argv
    or begin
        echo "usage: yabai_doctor [--repair]" >&2
        return 2
    end

    if set -q _flag_help
        echo "usage: yabai_doctor [--repair]"
        return 0
    end

    if test (count $argv) -ne 0
        echo "usage: yabai_doctor [--repair]" >&2
        return 2
    end

    if set -q _flag_repair
        __yabai_doctor_repair
        return $status
    end

    __yabai_doctor_check
end
