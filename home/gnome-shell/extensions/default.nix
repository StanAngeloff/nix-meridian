{
  imports = [
    ./activate-window-by-title.nix
    ./appindicator.nix
    ./bing-wallpaper-changer.nix
    ./clipboard-indicator.nix
    ./hide-universal-access.nix
    ./no-titlebar-when-maximized.nix
    ./soft-brightness-plus.nix
    ./tiling-assistant.nix
    ./window-title-is-back.nix
  ];

  dconf.settings."org/gnome/shell" = {
    disable-user-extensions = false;
  };
}
