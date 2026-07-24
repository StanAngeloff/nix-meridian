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
    "--model" "claude-opus-5[1m]"
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
  programs.zsh.shellAliases = {
    cc = launch claude-bubble bubbleArgs;
    ccc = launch claude-bubble (bubbleArgs ++ bypassArgs);

    # DEPRECATED fallback: today's un-bubbled behavior, kept until the bubble proves itself.
    # Delete these two lines (and this comment) once cc/ccc are trusted. Nothing else is exclusive to them —
    # bare `claude` keeps the inner-sandbox config in settings.nix,
    # and the package wrapper injects GH_TOKEN for all un-bubbled invocations.
    _cc = launch claude-code baseArgs;
    _ccc = launch claude-code (baseArgs ++ bypassArgs);
  };
}
