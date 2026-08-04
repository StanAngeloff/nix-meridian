{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (import ./json-utils.nix { inherit lib pkgs; }) mergeIntoLiveFile;

  jq = lib.getExe pkgs.jq;

  # NOTE: setsid detaches into its own session so the chime never blocks the hook;
  # PreToolUse blocks the tool prompt, so a synchronous audio player would delay the prompt appearing.
  chimeCmd = "${lib.getBin pkgs.util-linux}/bin/setsid --fork ${lib.getBin pkgs.pipewire}/bin/pw-play ${./audio/notifications/mixkit-clear-announce-tones-2861.mp3} >/dev/null 2>&1";

  stateCmd = pkgs.callPackage ./hooks/package.nix { };

  # Events that cannot be read off the pane title pipe their JSON to the dispatch script, which resolves a pane-option action; it reads stdin and takes no arguments.
  stateHook = {
    type = "command";
    command = lib.getExe stateCmd;
    timeout = 5;
  };

  chimeHook = {
    type = "command";
    command = chimeCmd;
    timeout = 5;
  };

  # A session has no way to learn its own id, but every hook payload carries one.
  # KEY=value lines appended to $CLAUDE_ENV_FILE join the session environment for the rest of the run, so $CLAUDE_SESSION_ID reaches shell commands; later lines win, which is what makes a clear or a resume land on the new id.
  # The variable is undocumented -- present and working in 2.1.219 -- hence the guard: if it ever disappears the hook is a no-op rather than a failure.
  # See "No way to access session ID from within a running session" https://github.com/anthropics/claude-code/issues/44607
  sessionIdHook = {
    type = "command";
    command = "[ -n \"\${CLAUDE_ENV_FILE:-}\" ] || exit 0; id=$(${jq} -r '.session_id // empty'); [ -n \"$id\" ] && printf 'CLAUDE_SESSION_ID=%s\\n' \"$id\" >> \"$CLAUDE_ENV_FILE\"; exit 0";
    timeout = 5;
  };

  hooks = {
    # nixfmt: off
    SessionStart = [
      { hooks = [ stateHook sessionIdHook ]; }
    ];
    UserPromptSubmit = [ { hooks = [ stateHook ]; } ];
    PreToolUse = [
      # Only the two tools that block on you reach the dispatch script; working comes from the pane title.
      { matcher = "AskUserQuestion|ExitPlanMode"; hooks = [ stateHook ]; }
      # Chime for the question prompt only.
      { matcher = "AskUserQuestion"; hooks = [ chimeHook ]; }
    ];
    PermissionRequest = [
      { hooks = [ chimeHook stateHook ]; }
    ];
    Elicitation = [ { hooks = [ stateHook ]; } ];
    Stop = [ { hooks = [ stateHook ]; } ];
    StopFailure = [ { hooks = [ stateHook ]; } ];
    SessionEnd = [ { hooks = [ stateHook ]; } ];
    # nixfmt: on, as: statements
  };
in
{
  # Guarded against a running session's own writes; see ./json-utils.nix.
  home.activation.updateClaudeCodeNotifications =
    lib.hm.dag.entryAfter [ "updateClaudeCodeSettings" ]
      (mergeIntoLiveFile {
        file = "${config.home.homeDirectory}/.claude/settings.json";
        label = "Claude Code hooks";
        # The whole hooks tree is ours: every entry below is generated here, so it is replaced rather than merged.
        filter = ".hooks = ${builtins.toJSON hooks}";
      });
}
