{ pkgs }:
# Creates the `default` tmux session when it is missing, for the desktop terminal that attaches to it and the phone hub that mirrors it.
#
# A server started here runs in a scope of its own that systemd-oomd avoids, the way systemd-run(1) starts screen.
# tmux built with systemd support (nixpkgs' withSystemd, on by default on Linux) moves every pane into its own tmux-spawn-<uuid>.scope.
# So under memory pressure a pane, an app or a Claude session goes first.
# Without this scope the server shares the scope of whichever terminal started it, and a kill there would end every pane at once.
#
# Every pane inherits the environment the server starts with, so the server gets its caller's.
# The tools are called by store path rather than put on PATH (runtimeInputs would prefix it), and this script's own shell level is dropped.
let
  systemdRun = "${pkgs.systemd}/bin/systemd-run";
  tmux = "${pkgs.tmux}/bin/tmux";
in
pkgs.writeShellApplication {
  name = "tmux-default-session";
  text = ''
    if ${tmux} has-session -t =default 2>/dev/null; then
      exit 0
    fi

    # bash counted itself in SHLVL; panes start as fresh shells.
    unset SHLVL

    if ${systemdRun} --user --scope --quiet --collect --slice=app.slice \
      --unit="tmux-server-$$" --description="tmux server" \
      --property=ManagedOOMPreference=avoid \
      ${tmux} new-session -d -s default -n default; then
      exit 0
    fi

    # Two terminals opened at once, or a terminal and the phone hub, race to create the session; the loser finds it here.
    if ${tmux} has-session -t =default 2>/dev/null; then
      exit 0
    fi

    # When the user manager cannot start the scope, an unprotected server still gives a working terminal.
    ${tmux} new-session -d -s default -n default
  '';
}
