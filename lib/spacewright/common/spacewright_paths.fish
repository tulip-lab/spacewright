function spacewright_initialize_paths --description "Resolve SpaceWright package, config, state, and integration roots"
    if not set -q SPACEWRIGHT_ROOT; or test -z "$SPACEWRIGHT_ROOT"
        set -l this_file (path resolve (status filename))
        set -gx SPACEWRIGHT_ROOT (path dirname (path dirname $this_file))
    end

    if not set -q SPACEWRIGHT_CONFIG_ROOT; or test -z "$SPACEWRIGHT_CONFIG_ROOT"
        if set -q XDG_CONFIG_HOME; and test -n "$XDG_CONFIG_HOME"
            set -gx SPACEWRIGHT_CONFIG_ROOT "$XDG_CONFIG_HOME/spacewright"
        else
            set -gx SPACEWRIGHT_CONFIG_ROOT "$HOME/.config/spacewright"
        end
    end

    if not set -q SPACEWRIGHT_STATE_ROOT; or test -z "$SPACEWRIGHT_STATE_ROOT"
        if set -q XDG_STATE_HOME; and test -n "$XDG_STATE_HOME"
            set -gx SPACEWRIGHT_STATE_ROOT "$XDG_STATE_HOME/spacewright"
        else
            set -gx SPACEWRIGHT_STATE_ROOT "$HOME/.local/state/spacewright"
        end
    end

    if not set -q SPACEWRIGHT_DISPLAY_PROFILES_ROOT; or test -z "$SPACEWRIGHT_DISPLAY_PROFILES_ROOT"
        set -gx SPACEWRIGHT_DISPLAY_PROFILES_ROOT "$SPACEWRIGHT_CONFIG_ROOT/displayprofiles"
    end

    if not set -q SPACEWRIGHT_SKHD_ROOT; or test -z "$SPACEWRIGHT_SKHD_ROOT"
        set -gx SPACEWRIGHT_SKHD_ROOT "$HOME/.config/skhd"
    end

    if not set -q SPACEWRIGHT_YABAI_ROOT; or test -z "$SPACEWRIGHT_YABAI_ROOT"
        set -gx SPACEWRIGHT_YABAI_ROOT "$HOME/.config/yabai"
    end
end

spacewright_initialize_paths
