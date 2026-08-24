{ lib, ... }:
{
  services.openssh = {
    enable = true;
    ports = [ 7222 ];
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

  networking.firewall.allowedTCPPorts = [ 7222 ];

  # Respond to mDNS hostname queries so the phone can resolve stan-latitude.local.
  services.avahi.publish = {
    enable = true;
    addresses = true;
    workstation = false;
  };

  # Phone keys are runtime-managed: setup-termux.sh POSTs the key to hub-server.py,
  # which writes it to ~/.ssh/authorized_keys with the forced command restriction.
  # No rebuild needed to register a new phone.
  services.openssh.authorizedKeysInHomedir = true;
}
