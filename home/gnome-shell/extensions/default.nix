{
  imports = [
    ./activate-window-by-title.nix
    ./clipboard-indicator.nix
    ./hide-universal-access.nix
    ./window-title-is-back.nix
  ];

  dconf.settings."org/gnome/shell" = {
    disable-user-extensions = false;
  };
}
