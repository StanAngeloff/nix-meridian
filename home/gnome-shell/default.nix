{ pkgs, lib, ... }:
{
  programs.gnome-shell = {
    enable = true;
    extensions = with pkgs.gnomeExtensions; [
      { package = clipboard-indicator; }
    ];
  };

  dconf.settings = {
    "org/gnome/shell" = {
      disable-user-extensions = false;
    };
    "org/gnome/desktop/interface" = {
      text-scaling-factor = lib.hm.gvariant.mkDouble["1.25"];
    };
    "org/gnome/desktop/interface" = {
      color-scheme = "prefer-dark";
    };
    "org/gnome/desktop/peripherals/keyboard" = {
      repeat-interval = lib.hm.gvariant.mkUint32 18;
      delay = lib.hm.gvariant.mkUint32 200;
    };
    "org/gnome/shell/extensions/clipboard-indicator" = {
      cache-size = 10;
      history-size = 50;
      move-item-first = true;
      paste-button = false;
      preview-size = 48;
      clear-history = [];
      next-entry = [];
      prev-entry = [];
      private-mode-binding = [];
      toggle-menu = [ "<Control><Shift><Alt>c" ];
    };
  };
}
