{
  lib,
  claude-code,
  claude-cc,
}:
let
  # _cc skips cc's per-model effort table, so it carries its own level; without one, Claude Code falls back to settings.json.
  fallbackArgs = [
    # nixfmt: off
    "--effort" "max"
    # nixfmt: on, as: shell-args
  ]
  ++ claude-cc.baseArgs;

  launch = exe: argv: "${lib.getExe exe} ${lib.escapeShellArgs argv}";
in
{
  programs.zsh.shellAliases = {
    # A short name for claude-cc (cc/package.nix), where every rule lives. A command named cc on PATH would shadow the C compiler.
    cc = "claude-cc";
    # DEPRECATED fallback: today's un-bubbled behavior, kept until the bubble proves itself.
    # Delete this line (and this comment) once cc is trusted. Nothing else is exclusive to it —
    # bare `claude` keeps the inner-sandbox config in settings.nix,
    # and the package wrapper injects GH_TOKEN for all un-bubbled invocations.
    _cc = launch claude-code fallbackArgs;
  };
}
