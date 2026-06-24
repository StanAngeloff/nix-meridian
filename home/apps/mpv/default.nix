{ pkgs, ... }:
{
  home.packages = with pkgs; [
    cine
    mpv
  ];
}
