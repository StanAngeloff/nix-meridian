{
  lib,
  writeShellApplication,
  coreutils,
  git,
  jq,
  tmux,
  pipewire,
  util-linux,
  ...
}:
let
  # Reuse the same chime asset the un-bubbled notifications use.
  chimeMp3 = ../../../audio/notifications/mixkit-clear-announce-tones-2861.mp3;
  # The relay applies the same pane-option actions the un-bubbled hook applies, so it calls the same script rather than reimplementing the state table. Imported with explicit arguments rather than callPackage because bubble/package.nix applies each module to a fixed attribute set that carries no callPackage; the cost is that a new dependency in hooks/package.nix must be threaded through here as well.
  stateCmd = import ../../../hooks/package.nix { inherit writeShellApplication jq tmux; };
  # The window rename waits for Claude Code to write the new session name, which it does after the hook has already returned.
  # Host-side is the only place that wait is free: the relay is a separate process, so nothing about the session start blocks on it.
  windowNameCmd = import ../../../hooks/window-name.nix {
    inherit
      writeShellApplication
      coreutils
      git
      jq
      tmux
      util-linux
      ;
  };
  # Its own writeShellApplication (not writeShellScript) so shellcheck gates it at build time too, and so its tmux/pw-play/setsid dependencies ride its own PATH instead of leaking into claude-bubble's runtime inputs.
  relay = writeShellApplication {
    name = "claude-bubble-relay";
    runtimeInputs = [
      coreutils
      tmux
      pipewire
      util-linux # setsid detaches the chime so it never blocks the relay loop
      stateCmd
      windowNameCmd
    ];
    text = builtins.readFile ./relay.sh;
  };
in
{
  runtimeInputs = [
    tmux
    util-linux # setsid launches the relay in its own process group; the after-run hook clears the pane options once bwrap exits
  ];
  substitutions = {
    bubbleRelay = lib.getExe relay;
    chimeMp3 = "${chimeMp3}";
  };
}
