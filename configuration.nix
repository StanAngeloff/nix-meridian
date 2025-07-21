{ config, lib, ... }:
{
  imports = [
    ./machines/stan-latitude/hardware-configuration.nix
    ./system
  ];

  # Enable the Flakes feature and the accompanying new nix command-line tool.
  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];

  # Define a user account. Don't forget to set a password with ‘passwd’.
  users.users.stan = with lib.lists; {
    isNormalUser = true;
    createHome = true;
    description = "Stan Angeloff";
    extraGroups =
      [
        "wheel"
      ]
      ++ optional config.networking.networkmanager.enable "networkmanager"
      ++ optional config.programs.adb.enable "adbusers"
      # NOTE: I want rootless podman, so any attempts to use Docker without `sudo` should fail.
      # ++ optional config.virtualisation.podman.dockerSocket.enable "podman"
    ;
  };

  # This value determines the NixOS release from which the default settings for stateful data,
  # like file locations and database versions on your system were taken.
  # It‘s perfectly fine and recommended to leave this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "24.11"; # Did you read the comment?
}
