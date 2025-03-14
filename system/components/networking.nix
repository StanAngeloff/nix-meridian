{ config, lib, ... }:
with lib.lists;
{
  # Pick only one of the below networking options.
  networking.networkmanager.enable = true; # Easiest to use and most distros use this by default.
  #networking.wireless.enable = true; # Enables wireless support via wpa_supplicant.

  # Enables DHCP on each ethernet and wireless interface.
  # In case of scripted networking (the default) this is the recommended approach.
  # When using systemd-networkd it's still possible to use this option,
  # but it's recommended to use it in conjunction with explicit per-interface declarations
  # with `networking.interfaces.<interface>.useDHCP`.
  networking.useDHCP = lib.mkDefault true;
  # networking.interfaces.ens3.useDHCP = lib.mkDefault true;

  networking.firewall = {
    enable = true;

    #allowedTCPPorts = [ ];
    #allowedTCPPortRanges = [ ];

    #allowedUDPPorts = [ ];
    #allowedUDPPortRanges = [ ];

    # > [..] If the interface name ends in a "+", then any interface which begins with this name will match.
    # Learn more at `man iptables`
    interfaces."podman+" = {
      allowedUDPPorts =
        [ ]
        # > on non default networks [..] you still need to open the ports for the specific network interface podman creates [..]
        # Learn more at https://github.com/NixOS/nixpkgs/issues/226365#issuecomment-2164985192
        ++ optional config.virtualisation.podman.defaultNetwork.settings.dns_enabled 53;
    };
  };
}
