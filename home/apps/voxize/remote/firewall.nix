{ config, ... }:
{
  # The Voxize Remote server's port, on the tailnet only (the server also refuses anything Tailscale cannot vouch for).
  # The effective rule only because tailscaled runs in nodivert mode (system/components/tailscale.nix).
  networking.firewall.interfaces.${config.services.tailscale.interfaceName}.allowedTCPPorts = [
    (import ./port.nix)
  ];
}
