# Tailscale mesh VPN
#
# This machine is only ever a destination: no exit node, no subnet routes.
# The flags below are applied by the tailscaled-set oneshot on every boot.
#
# The very first `tailscale up` must repeat them: before a control server is set it sends full preferences built from its own defaults.
{
  services.tailscale = {
    enable = true;
    # UDP 41641, so peers can reach this machine directly instead of through a relay.
    openFirewall = true;
    disableUpstreamLogging = true;
    extraSetFlags = [
      # tailscale up/status/set without sudo.
      "--operator=stan"
      # In the default "on" mode tailscaled inserts a jump at the top of INPUT to a chain that accepts everything on
      # tailscale0, ahead of nixos-fw. "nodivert" keeps its chains but not the jumps, so the NixOS firewall decides.
      "--netfilter-mode=nodivert"
      # This machine never needs tailnet names; leave systemd-resolved exactly as NixOS configures it.
      "--accept-dns=false"
    ];
  };
}
