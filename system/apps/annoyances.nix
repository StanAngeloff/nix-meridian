{
  imports = [
    # Brave uses system-wide policies which are linked outside of Home Manager.
    ../../home/apps/brave/policies.nix
    # Locked-down sshd for phone remote access to Claude Code sessions.
    ../../home/apps/claude-code/remote/sshd.nix
  ];
}
