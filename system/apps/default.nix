{ pkgs, ... }:
{
  imports = [
    ./annoyances.nix
  ];

  # Allow unfree packages
  nixpkgs.config.allowUnfree = true;

  # NOTE: nix-ld allows running unpatched dynamic binaries on NixOS. This is a prerequisite for `aapt` when Expo does an Android build.
  programs.nix-ld.enable = true;

  # List packages to exclude from the default Gnome desktop environment.
  environment.gnome.excludePackages = with pkgs; [
    evince
  ];
}
