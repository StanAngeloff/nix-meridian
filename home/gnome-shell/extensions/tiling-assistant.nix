{ pkgs, ... }:
{
  programs.gnome-shell.extensions = with pkgs.gnomeExtensions; [
    { package = tiling-assistant; }
  ];
}
