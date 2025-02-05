{ config, lib, ... }:
let
  nixvim = import (
    builtins.fetchGit {
      url = "https://github.com/nix-community/nixvim";
      ref = "nixos-24.11";
    }
  );
in
{
  imports = [
    ./machines/stan-latitude
    ./system
    <home-manager/nixos>
  ];

  # Define a user account. Don't forget to set a password with ‘passwd’.
  users.users.stan = {
    isNormalUser = true;
    createHome = true;
    description = "Stan Angeloff";
    extraGroups = [
      "wheel"
    ] ++ lib.lists.optional config.networking.networkmanager.enable "networkmanager";
  };

  home-manager.users.stan =
    { ... }:
    {
      imports = [
        nixvim.homeManagerModules.nixvim
        ./home
      ];
    };

  # This value determines the NixOS release from which the default settings for stateful data,
  # like file locations and database versions on your system were taken.
  # It‘s perfectly fine and recommended to leave this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "24.11"; # Did you read the comment?
}
