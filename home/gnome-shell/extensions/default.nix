{
  imports = [
    ./activate-window-by-title.nix
    ./appindicator.nix
    ./clipboard-indicator.nix
    ./hide-universal-access.nix
    ./no-titlebar-when-maximized.nix
    ./tiling-assistant.nix
    ./window-title-is-back.nix
  ];

  dconf.settings."org/gnome/shell" = {
    disable-user-extensions = false;
  };
}
