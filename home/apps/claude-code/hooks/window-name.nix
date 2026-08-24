{
  writeShellApplication,
  coreutils,
  git,
  jq,
  tmux,
  util-linux,
}:
# Its own file rather than an inline writeShellApplication in notifications.nix, the way the smaller
# worktree hook is defined: three callers need this one -- the hook, the bubble relay, and the zsh
# launcher that names the window before Claude Code starts.
writeShellApplication {
  name = "claude-window-name";

  runtimeInputs = [
    coreutils # sleep, while waiting for Claude Code to write the session name
    git # the repository half of the window name
    jq
    tmux
    util-linux # setsid detaches the wait when there is no relay to do it
  ];

  text = builtins.readFile ./claude-window-name.sh;
}
