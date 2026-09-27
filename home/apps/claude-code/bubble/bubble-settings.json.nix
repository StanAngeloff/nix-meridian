{
  lib,
  pkgs,
  claude-arbiter,
}:
# High-precedence CLI --settings layer for bubbled sessions.
# It lives in the Nix store and the launcher passes it, so no session can edit it; it outranks user, project and local settings.
(pkgs.formats.json { }).generate "claude-bubble-settings.json" {
  sandbox = {
    # The bubble replaces the inner Bash sandbox, whose false positives trained constant dangerouslyDisableSandbox use.
    enabled = false;
  };
  # cc launches with --dangerously-skip-permissions; skip the warning dialog that comes with it.
  skipDangerousModePermissionPrompt = true;
  # A project-local `disableAllHooks: true` would switch off every hook defined outside managed settings,
  # the arbiter included - this layer outranks it.
  disableAllHooks = false;
  hooks.PreToolUse = [
    {
      # Every tool call, subagents' included; see arbiter/claude-arbiter.sh.
      matcher = "*";
      hooks = [
        {
          type = "command";
          command = lib.getExe claude-arbiter;
          timeout = 30;
        }
      ];
    }
  ];
}
