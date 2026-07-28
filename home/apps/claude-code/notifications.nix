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

  hooks = {
    # nixfmt: off
    SessionStart = [ { hooks = [ stateHook ]; } ];
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
