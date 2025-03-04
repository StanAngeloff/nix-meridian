{ lib, ... }:
with lib.hm.gvariant;
{
  dconf.settings = with lib.hm.gvariant; {
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
      clock-show-date = false;
      clock-show-weekday = false;
      color-scheme = "prefer-dark";
      enable-hot-corners = false;
      gtk-enable-primary-paste = false;
      show-battery-percentage = true;
      text-scaling-factor = 1.00;
    };
    "org/gnome/desktop/peripherals/keyboard" = {
      delay = mkUint32 200;
      repeat-interval = mkUint32 18;
    };
    "org/gnome/desktop/session" = {
      idle-delay = mkUint32 0;
    };
    "org/gnome/desktop/wm/preferences" = {
      num-workspaces = 4;
    };
    "org/gnome/mutter" = {
      attach-modal-dialogs = true;
      dynamic-workspaces = false;
      edge-tiling = false;
      workspaces-only-on-primary = true;
    };
    "org/gnome/nautilus/list-view" = {
      use-tree-view = true;
    };
    "org/gnome/shell" = {
      favorite-apps = [
        "brave-browser.desktop"
        "code.desktop"
        "slack.desktop"
        "thunderbird.desktop"
        "org.gnome.Nautilus.desktop"
      ];
    };
    "org/gnome/shell/app-switcher" = {
      current-workspace-only = true;
    };
    "org/gnome/settings-daemon/plugins/color" = {
      night-light-enabled = true;
      night-light-schedule-automatic = true;
    };
    "org/gnome/settings-daemon/plugins/power" = {
      idle-dim = false;
    };
  };
}
