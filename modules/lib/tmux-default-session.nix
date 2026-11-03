{ pkgs }:
# Creates the `default` tmux session when it is missing, for the desktop terminal that attaches to it and the phone hub that mirrors it.
#
# A server started here runs in a scope of its own that systemd-oomd avoids, the way systemd-run(1) starts screen.
# tmux built with systemd support (nixpkgs' withSystemd, on by default on Linux) moves every pane into its own tmux-spawn-<uuid>.scope.
# So under memory pressure a pane, an app or a Claude session goes first.
# Without this scope the server shares the scope of whichever terminal started it, and a kill there would end every pane at once.
pkgs.writeShellApplication {
  name = "tmux-default-session";
  runtimeInputs = [
    pkgs.systemd
    pkgs.tmux
  ];
  text = ''
    if tmux has-session -t =default 2>/dev/null; then
      exit 0
    fi

    if systemd-run --user --scope --quiet --collect --slice=app.slice \
      --unit="tmux-server-$$" --description="tmux server" \
      --property=ManagedOOMPreference=avoid \
      tmux new-session -d -s default -n default; then
      exit 0
    fi

    # Two terminals opened at once, or a terminal and the phone hub, race to create the session; the loser finds it here.
    if tmux has-session -t =default 2>/dev/null; then
      exit 0
    fi

    # When the user manager cannot start the scope, an unprotected server still gives a working terminal.
    tmux new-session -d -s default -n default
  '';
}
