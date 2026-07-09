{
  lib,
  writeShellApplication,
  bubblewrap,
  coreutils,
  gnupg,
  libsecret,
  tmux,
  pipewire,
  util-linux,
  claude-code,
  # Extra keyring var names to inject into the bubble (future opt-in). Empty for now.
  secretVars ? [ ],
}:
# Builds `claude-bubble`, the host-side bubblewrap wrapper, plus the host-side notification
# relay it starts. See bubble.sh / relay.sh for the rationale. bubble.sh's @placeholder@
# slots (store paths + the inject list) are filled below via builtins.replaceStrings.
let
  # Reuse the same chime asset the un-bubbled notifications use.
  chimeMp3 = ../audio/notifications/mixkit-clear-announce-tones-2861.mp3;
  # Its own writeShellApplication (not writeShellScript) so shellcheck gates it at build time
  # too, and so its tmux/pw-play/setsid dependencies ride its own PATH instead of leaking
  # into claude-bubble's runtime inputs.
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
writeShellApplication {
  name = "claude-bubble";
  runtimeInputs = [
    bubblewrap
    coreutils
    gnupg
    libsecret
    tmux # the epilogue clears @claude-state after bwrap exits
  ];
  # bubble.sh carries @placeholder@ slots for the store paths it needs; fill them with a pure
  # builtins.replaceStrings over the source (no import-from-derivation, unlike readFile'ing a
  # pkgs.replaceVars derivation).
  text =
    builtins.replaceStrings
      [ "@claudeBin@" "@bubbleRelay@" "@chimeMp3@" "@bubbleInject@" ]
      [
        (lib.getExe claude-code)
        (lib.getExe relay)
        "${chimeMp3}"
        (lib.concatStringsSep " " secretVars)
      ]
      (builtins.readFile ./bubble.sh);
}
