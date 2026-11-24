{
  config,
  lib,
  osConfig,
  pkgs,
  ...
}:
let
  voxize-remote = pkgs.callPackage ./package.nix { };
  port = import ./port.nix;
in
{
  # Only the command: the package carries voxize's own Python tree too (it is voxize's environment), which would clash
  # with pkgs.voxize in the profile.
  home.packages = [
    (pkgs.runCommand "voxize-remote-command" { meta.mainProgram = "voxize-remote"; } ''
      mkdir -p $out/bin
      ln -s ${lib.getExe voxize-remote} $out/bin/voxize-remote
    '')
  ];

  # The server starts on demand: systemd holds its two sockets and starts voxize-remote.service at the first connection
  # (a client dialling in, or `voxize-remote pair|status|devices` on this machine); it exits after 5 minutes with none.
  # Two socket units because FileDescriptorName is per unit; the server tells its sockets apart by those names.
  systemd.user.sockets.voxize-remote-clients = {
    Unit.Description = "Voxize Remote: clients dialling in over Tailscale (firewall.nix opens the port there only)";
    Socket = {
      ListenStream = toString port;
      FileDescriptorName = "clients";
      Service = "voxize-remote.service";
    };
    Install.WantedBy = [ "sockets.target" ];
  };
  systemd.user.sockets.voxize-remote-control = {
    Unit.Description = "Voxize Remote: the control socket voxize-remote pair, status and devices talk to";
    Socket = {
      ListenStream = "%t/voxize-remote.sock";
      SocketMode = "0600";
      FileDescriptorName = "control";
      Service = "voxize-remote.service";
    };
    Install.WantedBy = [ "sockets.target" ];
  };
  systemd.user.services.voxize-remote = {
    Unit = {
      Description = "Voxize Remote server: dictation from the paired client into the tmux pane its Termux shows";
      Requires = [
        "voxize-remote-clients.socket"
        "voxize-remote-control.socket"
      ];
    };
    Service = {
      ExecStart = "${lib.getExe voxize-remote} serve --systemd --idle-exit 300";
      Sockets = [
        "voxize-remote-clients.socket"
        "voxize-remote-control.socket"
      ];
      # The tmux client must match the running tmux server's version, and identify_peer asks Tailscale's own CLI.
      Environment = [
        "PATH=${
          lib.makeBinPath [
            config.programs.tmux.package
            osConfig.services.tailscale.package
          ]
        }"
      ]
      # secureSocket puts tmux's socket under the runtime directory through a shell-profile variable, which reaches
      # the user manager only if the desktop session happens to import it.
      ++ lib.optional config.programs.tmux.secureSocket "TMUX_TMPDIR=%t";
      # No PrivateTmp or ProtectHome: it reaches tmux's socket, the keyring over D-Bus, and Voxize's state.
      NoNewPrivileges = true;
      LockPersonality = true;
      RestrictRealtime = true;
      RestrictSUIDSGID = true;
      SystemCallArchitectures = "native";
      RestrictAddressFamilies = [
        "AF_UNIX"
        "AF_INET"
        "AF_INET6"
        "AF_NETLINK"
      ];
    };
  };
}
