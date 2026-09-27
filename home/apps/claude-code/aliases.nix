{
  lib,
  claude-code,
  claude-bubble,
  bubbleSettings,
  baseModel,
}:
let
  # No --effort here: cc gets exactly one from the per-model table in initialize.zsh.
  baseArgs = [
    # nixfmt: off
    "--model" baseModel
    # nixfmt: on, as: shell-args
  ];
  # _cc skips that table, so it carries its own level; without one, Claude Code falls back to settings.json.
  fallbackArgs = [
    # nixfmt: off
    "--effort" "max"
    # nixfmt: on, as: shell-args
  ]
  ++ baseArgs;
  # Inside the bubble Claude Code skips permission prompts, though deny and ask rules still apply;
  # the bubble's --settings layer turns the inner Bash sandbox off and registers the arbiter.
  bubbleArgs = baseArgs ++ [
    # nixfmt: off
    "--dangerously-skip-permissions"
    "--settings" "${bubbleSettings}"
    # nixfmt: on, as: shell-args
  ];

  launch = exe: argv: "${lib.getExe exe} ${lib.escapeShellArgs argv}";
in
{
  programs.zsh.initContent = lib.mkOrder 1500 ''
    # Words the launcher hands to a subcommand handler (bubble/package.nix); initialize.zsh mirrors its rule.
    typeset -ga _claude_subcommand_names=( ${lib.concatStringsSep " " claude-bubble.subcommandNames} )
    source ${./initialize.zsh}

    function cc() {
      local -a _cli_args=( "$@" )
      _claude_expand_model_aliases ${lib.escapeShellArg baseModel}
      _claude_bubble_initialize "''${_cli_args[@]}" || return
      ${launch claude-bubble bubbleArgs} "''${_cli_args[@]}"
    }
  '';

  programs.zsh.shellAliases = {
    # DEPRECATED fallback: today's un-bubbled behavior, kept until the bubble proves itself.
    # Delete this line (and this comment) once cc is trusted. Nothing else is exclusive to it —
    # bare `claude` keeps the inner-sandbox config in settings.nix,
    # and the package wrapper injects GH_TOKEN for all un-bubbled invocations.
    _cc = launch claude-code fallbackArgs;
  };
}
