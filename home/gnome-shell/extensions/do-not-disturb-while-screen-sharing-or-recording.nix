{ pkgs, ... }:
{
  programs.gnome-shell.extensions = with pkgs.gnomeExtensions; [
    { package = do-not-disturb-while-screen-sharing-or-recording; }
  ];
}
