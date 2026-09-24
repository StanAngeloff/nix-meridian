{
  lib,
  claude-code,
  claude-bubble,
  bubbleSettings,
  baseModel,
}:
let
  # No --effort here: cc/ccc get exactly one from the per-model table in initialize.zsh.
  baseArgs = [
    # nixfmt: off
    "--model" baseModel
    # nixfmt: on, as: shell-args
  ];
  # _cc/_ccc skip that table, so they carry their own level; without one, Claude Code falls back to settings.json.
  fallbackArgs = [
    # nixfmt: off
    "--effort" "max"
    # nixfmt: on, as: shell-args
  ]
  ++ baseArgs;
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
    source ${./initialize.zsh}

    function cc() {
      local -a _cli_args=( "$@" )
      _claude_expand_model_aliases ${lib.escapeShellArg baseModel}
      _claude_bubble_initialize "''${_cli_args[@]}" || return
      ${launch claude-bubble bubbleArgs} "''${_cli_args[@]}"
    }

    function ccc() {
      local -a _cli_args=( "$@" )
      _claude_expand_model_aliases ${lib.escapeShellArg baseModel}
      _claude_bubble_initialize "''${_cli_args[@]}" || return
      ${launch claude-bubble (bubbleArgs ++ bypassArgs)} "''${_cli_args[@]}"
    }
  '';

  programs.zsh.shellAliases = {
    # DEPRECATED fallback: today's un-bubbled behavior, kept until the bubble proves itself.
    # Delete these two lines (and this comment) once cc/ccc are trusted. Nothing else is exclusive to them —
    # bare `claude` keeps the inner-sandbox config in settings.nix,
    # and the package wrapper injects GH_TOKEN for all un-bubbled invocations.
    _cc = launch claude-code fallbackArgs;
    _ccc = launch claude-code (fallbackArgs ++ bypassArgs);
  };
}
