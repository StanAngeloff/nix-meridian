{ pkgs, ... }:
{
  home.packages = [
    pkgs.proton-pass
    pkgs.protonvpn-gui
  ];
}
