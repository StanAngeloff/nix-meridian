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
    typeset -a bubble_command=( ${lib.getExe claude-bubble} ${lib.escapeShellArgs bubbleArgs} "''${_cli_args[@]}" )
    if [[ -z "$_claude_renamed_window_id" ]]; then exec "''${bubble_command[@]}"; fi

    # cc renamed the tmux window, so it stays alive until the session ends to give the window its old name back.
    # zsh skips the EXIT trap when INT or TERM ends it, so both signals become a plain exit.
    trap _claude_restore_window_name EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM
    "''${bubble_command[@]}"
  '';
  checkPhase = ''
    ${lib.getExe zsh} -n "$target"
  '';
  passthru = { inherit baseArgs; };
  meta.mainProgram = "claude-cc";
}
