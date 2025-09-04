{ config, pkgs-unstable, ... }:
{
  programs.nh = {
    enable = true;
    package = pkgs-unstable.nh;

    flake = "${config.home.homeDirectory}/nix-meridian/flake.nix";

    clean = {
      enable = true;
      dates = "weekly";
      extraArgs = "--keep 5 --keep-since 30d"; # NOTE: Add "--optimise" after https://github.com/nix-community/nh/pull/381 is released.
    };
  };
}
