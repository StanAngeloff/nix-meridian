{ pkgs, ... }:
{
  imports = [
    ./extensions
    ./keybindings.nix
    ./settings.nix
  ];

  programs.gnome-shell.enable = true;

  # See https://wiki.nixos.org/wiki/Cursor_Themes
  home.file.".icons/default".source = "${pkgs.vanilla-dmz}/share/icons/Vanilla-DMZ";
}
