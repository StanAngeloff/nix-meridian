{ pkgs, ... }:
{
  imports = [
    ./annoyances.nix
  ];

  # Allow unfree packages
  nixpkgs.config.allowUnfree = true;

  programs.nix-ld.enable = true;

  # List packages installed in system profile. To search, run:
  # $ nix search wget
  environment.systemPackages = with pkgs; [
    libappindicator-gtk2 # Library to allow applications to export a menu into the Unity Menu bar.
    libappindicator-gtk3 # Library to allow applications to export a menu into the Unity Menu bar.
  ];
}
