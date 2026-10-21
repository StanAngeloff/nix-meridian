# claude-cc: the command behind the cc alias, which starts every bubbled session.
# It expands model aliases, picks the per-model effort and checks the session-name rule (../initialize.zsh),
# then hands the arguments to the claude-bubble launcher. It is a zsh script because the rules in initialize.zsh are zsh.
{
  lib,
  writeTextFile,
  zsh,
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
  # Inside the bubble Claude Code skips permission prompts, though deny and ask rules still apply;
  # the bubble's --settings layer turns the inner Bash sandbox off and registers the arbiter.
  bubbleArgs = baseArgs ++ [
    # nixfmt: off
    "--dangerously-skip-permissions"
    "--settings" "${bubbleSettings}"
    # nixfmt: on, as: shell-args
  ];
in
writeTextFile {
  name = "claude-cc";
  destination = "/bin/claude-cc";
  executable = true;
  text = ''
    #!${lib.getExe zsh}
    # Words the launcher hands to a subcommand handler (bubble/package.nix); initialize.zsh mirrors its rule.
    typeset -ga _claude_subcommand_names=( ${lib.concatStringsSep " " claude-bubble.subcommandNames} )
    source ${../initialize.zsh}

    typeset -ga _cli_args=( "$@" )
    _claude_expand_model_aliases ${lib.escapeShellArg baseModel}
    _claude_bubble_initialize "''${_cli_args[@]}" || exit
    exec ${lib.getExe claude-bubble} ${lib.escapeShellArgs bubbleArgs} "''${_cli_args[@]}"
  '';
  checkPhase = ''
    ${lib.getExe zsh} -n "$target"
  '';
  passthru = { inherit baseArgs; };
  meta.mainProgram = "claude-cc";
}
