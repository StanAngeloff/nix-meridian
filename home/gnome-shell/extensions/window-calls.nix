{ pkgs-unstable, ... }:
{
  programs.gnome-shell.extensions = with pkgs-unstable.gnomeExtensions; [
    { package = window-calls; }
  ];
}
