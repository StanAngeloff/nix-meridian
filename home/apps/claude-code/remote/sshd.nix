{ config, ... }:
{
  services.openssh = {
    enable = true;
    ports = [ 7222 ];
    # Defaults to true, which adds the ports to the global allowedTCPPorts; the rule below opens them on the tailnet only.
    openFirewall = false;
    settings = {
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
      PermitRootLogin = "no";
      AllowUsers = [ "stan" ];
      AllowTcpForwarding = false;
      AllowAgentForwarding = false;
      AllowStreamLocalForwarding = false;
    };
  };

  # The effective gate only because tailscaled runs in nodivert mode (system/components/tailscale.nix).
  networking.firewall.interfaces.${config.services.tailscale.interfaceName}.allowedTCPPorts = [
    7222
  ];

  # Phone keys are runtime-managed: `cc remote setup` (remote/pairing_server.py) writes the phone's key to
  # ~/.ssh/authorized_keys with the forced command restriction. No rebuild needed to register a new phone.
  services.openssh.authorizedKeysInHomedir = true;
}
