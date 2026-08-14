{
  lib,
  claude-code,
  claude-bubble,
  bubbleSettings,
}:
let
  baseArgs = [
    # nixfmt: off
    "--effort" "max"
    "--model" "claude-opus-4-6[1m]"
    # nixfmt: on, as: shell-args
  ];
  # NOTE: The bubble adds OS-isolation mode and the inner-Bash-sandbox-off settings on top.
  bubbleArgs = baseArgs ++ [
    # nixfmt: off
    "--permission-mode" "auto"
    "--settings" "${bubbleSettings}"
    # nixfmt: on, as: shell-args
  ];
  bypassArgs = [ "--dangerously-skip-permissions" ];

  launch = exe: argv: "${lib.getExe exe} ${lib.escapeShellArgs argv}";
in
{
  programs.zsh.initContent = lib.mkOrder 1500 ''
    function _claude_bubble_initialize() {
      emulate -L zsh

      local has_session_flag=0
      local session_name=""
      local i
      for (( i=1; i <= $#; i++ )); do
        case "''${@[$i]}" in
          -n|--name|-r|--resume)
            has_session_flag=1
            if (( i < $# )); then
              local next="''${@[$i+1]}"
              [[ "$next" != --* ]] && session_name="$next"
            fi
            break
            ;;
          --name=*|--resume=*)
            has_session_flag=1
            session_name="''${''${@[$i]}#*=}"
            break
            ;;
        esac
      done

      local is_strict=0
      if [[ -n "$CLAUDE_BUBBLE_STRICT" && "$CLAUDE_BUBBLE_STRICT" != "0" \
         && "''${(L)CLAUDE_BUBBLE_STRICT}" != "false" ]]; then
        is_strict=1
      fi

      if (( is_strict && ! has_session_flag )); then
        print -u2 "cc: CLAUDE_BUBBLE_STRICT is set — pass -n/--name or -r/--resume"
        return 1
      fi

      if [[ -n "$CLAUDE_BUBBLE_TMUX" && "$CLAUDE_BUBBLE_TMUX" != "0" \
         && "''${(L)CLAUDE_BUBBLE_TMUX}" != "false" \
         && -n "$TMUX" && -n "$session_name" ]]; then
        local git_common
        git_common=$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null)
        if [[ -n "$git_common" ]]; then
          local repository_name="''${''${git_common%/.git}:t}"
          local normalized="''${session_name%%[/@#.!?[:space:]]*}"
          if [[ -n "$repository_name" && -n "$normalized" ]]; then
            tmux rename-window "''${repository_name}@''${normalized}"
          fi
        fi
      fi
    }

    function cc() {
      _claude_bubble_initialize "$@" || return
      ${launch claude-bubble bubbleArgs} "$@"
    }

    function ccc() {
      _claude_bubble_initialize "$@" || return
      ${launch claude-bubble (bubbleArgs ++ bypassArgs)} "$@"
    }
  '';

  programs.zsh.shellAliases = {
    # DEPRECATED fallback: today's un-bubbled behavior, kept until the bubble proves itself.
    # Delete these two lines (and this comment) once cc/ccc are trusted. Nothing else is exclusive to them —
    # bare `claude` keeps the inner-sandbox config in settings.nix,
    # and the package wrapper injects GH_TOKEN for all un-bubbled invocations.
    _cc = launch claude-code baseArgs;
    _ccc = launch claude-code (baseArgs ++ bypassArgs);
  };
}
