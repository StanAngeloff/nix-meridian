{
  # Pick only one of the below networking options.
  networking.networkmanager.enable = true; # Easiest to use and most distros use this by default.
  #networking.wireless.enable = true; # Enables wireless support via wpa_supplicant.

  networking.firewall = {
    enable = true;

    #allowedTCPPorts = [ ];
    #allowedTCPPortRanges = [ ];

    #allowedUDPPorts = [ ];
    #allowedUDPPortRanges = [ ];
  };
}
