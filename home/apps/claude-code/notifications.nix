{
  config,
  lib,
  pkgs,
  ...
}:
let
  # NOTE: setsid detaches into its own session so the chime never blocks the hook;
  # PreToolUse blocks the tool prompt, so a synchronous audio player would delay the prompt appearing.
  chimeCmd = "${lib.getBin pkgs.util-linux}/bin/setsid --fork ${lib.getBin pkgs.pipewire}/bin/pw-play ${./audio/notifications/mixkit-clear-announce-tones-2861.mp3} >/dev/null 2>&1";

  stateCmd = pkgs.callPackage ./hooks/package.nix { };

  # Every state-changing event pipes its JSON to the dispatch script, which decides the state and ignores subagent-originated events;
  # it reads stdin and takes no arguments.
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

  hooks = {
    # nixfmt: off
    SessionStart = [ { hooks = [ stateHook ]; } ];
    UserPromptSubmit = [ { hooks = [ stateHook ]; } ];
    PreToolUse = [
      # All tools go to the dispatch script; it decides working or blocked from tool_name.
      { hooks = [ stateHook ]; }
      # Chime for the question prompt only.
      { matcher = "AskUserQuestion"; hooks = [ chimeHook ]; }
    ];
    PostToolUse = [ { hooks = [ stateHook ]; } ];
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
  home.activation.updateClaudeCodeNotifications =
    let
      jq = lib.getExe pkgs.jq;
      sponge = "${lib.getBin pkgs.moreutils}/bin/sponge";
    in
    lib.hm.dag.entryAfter [ "updateClaudeCodeSettings" ] ''
      settingsFile="${config.home.homeDirectory}/.claude/settings.json"

      ${jq} ${lib.strings.escapeShellArg ".hooks = ${builtins.toJSON hooks}"} "$settingsFile" | ${sponge} "$settingsFile"
    '';
}
