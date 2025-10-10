{ config, lib, ... }:
with lib.lists;
{
  networking.useDHCP = lib.mkDefault true; # NOTE: NetworkManager, if enabled, will override this to `false`, so use a default value here.
  networking.networkmanager.enable = true;

  # Learn more at https://nixos.wiki/wiki/Printing#Enable_autodiscovery_of_network_printers
  services.avahi = {
    enable = true;
    nssmdns4 = true;
    openFirewall = true;

    # NOTE: Avahi is also useful for mDNS service discovery in local networks and required by programs such as UxPlay.
    #       I DO NOT enable the "publish" option, however, as I DO NOT want this machine to be discoverable by other devices on the network.
    #       This may be revisited in the future if I want to use AirPlay or similar technologies.
  };

  networking.firewall = {
    enable = true;

    # NOTE: The allowed TCP/UDP ports (and ranges) options below open ports globally (to all sources).
    #       There is no way to restrict by source subnet using configuration only.
    allowedTCPPorts = [ ];
    allowedTCPPortRanges = [
      # nixfmt: off
      { from = 8080; to = 8081; } # Expo Go
      { from = 54321; to = 54324; } # Supabase
      # nixfmt: on
    ];

    allowedUDPPorts = [ ];
    allowedUDPPortRanges = [ ];

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
