{
  lib,
  writeShellApplication,
  coreutils,
  tmux,
  pipewire,
  util-linux,
  ...
}:
let
  # Reuse the same chime asset the un-bubbled notifications use.
  chimeMp3 = ../../../audio/notifications/mixkit-clear-announce-tones-2861.mp3;
  # Its own writeShellApplication (not writeShellScript) so shellcheck gates it at build time too, and so its tmux/pw-play/setsid dependencies ride its own PATH instead of leaking into claude-bubble's runtime inputs.
  relay = writeShellApplication {
    name = "claude-bubble-relay";
    runtimeInputs = [
      coreutils
      tmux
      pipewire
      util-linux # setsid detaches the chime so it never blocks the relay loop
    ];
    text = builtins.readFile ./relay.sh;
  };
in
{
  runtimeInputs = [ tmux ]; # after-run.sh clears @claude-state once bwrap exits
  substitutions = {
    bubbleRelay = lib.getExe relay;
    chimeMp3 = "${chimeMp3}";
  };
}
