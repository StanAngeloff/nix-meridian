{
  imports = [
    ./activate-window-by-title.nix
    ./appindicator.nix
    ./bing-wallpaper-changer.nix
    ./bluetooth-battery-meter.nix
    ./clipboard-indicator.nix
    ./do-not-disturb-while-screen-sharing-or-recording.nix
    ./hide-universal-access.nix
    ./notification-timeout.nix
    ./soft-brightness-plus.nix
    ./tiling-assistant.nix
    ./window-calls.nix
  ];

  dconf.settings."org/gnome/shell" = {
    disable-user-extensions = false;
  };
}
