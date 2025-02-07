{ lib, ... }:
with lib.hm.gvariant;
{
  dconf.settings = {
    "org/gnome/desktop/input-sources" = {
      per-window = true; # Use different input sources for each window.
      mru-sources = [
        (mkTuple [
          "xkb"
          "us+euro"
        ])
        (mkTuple [
          "xkb"
          "bg+phonetic"
        ])
      ];
      sources = [
        (mkTuple [
          "xkb"
          "us+euro"
        ])
        (mkTuple [
          "xkb"
          "bg+phonetic"
        ])
      ];
      xkb-options = [
        # List of XKB options:
        #
        # Each option is an XKB option string as defined by xkeyboard-config’s rules files.
        # See http://manpages.ubuntu.com/manpages/trusty/man7/xkeyboard-config.7.html
        #
        # - Switching to another layout: Caps Lock (grp:caps_toggle); Mata+Space (grp:win_space_toggle)
        # - Use keyboard LED to show alternative layout: Caps Lock (grp_led:caps)
        # - Position of Compose key: Right Alt (compose:ralt)
        #
        "grp:caps_toggle"
        "grp_led:caps"
        "grp:win_space_toggle"
        "compose:ralt"
      ];
    };
    "org/gnome/desktop/interface" = {
      color-scheme = "prefer-dark";
      cursor-theme = "DMZ-White";
      cursor-size = 32;
      enable-hot-corners = false;
      show-battery-percentage = true;
      clock-show-date = false;
      clock-show-weekday = false;
      text-scaling-factor = 1.25;
    };
    "org/gnome/desktop/peripherals/keyboard" = {
      delay = lib.hm.gvariant.mkUint32 200;
      repeat-interval = lib.hm.gvariant.mkUint32 18;
    };
    "org/gnome/nautilus/list-view" = {
      use-tree-view = true;
    };
    "org/gnome/shell" = {
      favorite-apps = [
        "google-chrome.desktop"
        "firefox.desktop"
        "code.desktop"
        "slack.desktop"
        "org.gnome.Nautilus.desktop"
      ];
    };
    "org/gnome/shell/app-switcher" = {
      current-workspace-only = true;
    };
    "org/gnome/shell/overrides" = {
      attach-modal-dialogs = true;
      edge-tiling = false;
      workspaces-only-on-primary = true;
    };
  };
}
