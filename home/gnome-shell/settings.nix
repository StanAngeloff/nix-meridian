{ lib, ... }:
with lib.hm.gvariant;
{
  dconf.settings = {
    "org/gnome/desktop/input-sources" = {
      per-window = true;  # Use different input sources for each window.
      mru-sources = [ (mkTuple [ "xkb" "us+euro" ]) (mkTuple [ "xkb" "bg+phonetic" ]) ];
      sources = [ (mkTuple [ "xkb" "us+euro" ]) (mkTuple [ "xkb" "bg+phonetic" ]) ];
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
      enable-hot-corners = false;
      text-scaling-factor = 1.25;
    };
    "org/gnome/desktop/peripherals/keyboard" = {
      delay = lib.hm.gvariant.mkUint32 200;
      repeat-interval = lib.hm.gvariant.mkUint32 18;
    };
    "org/gnome/desktop/wm/keybindings" = {
      begin-move = [];
      begin-resize = [];
      cycle-group = [];
      cycle-group-backward = [];
      cycle-panels = [];
      cycle-windows = [ "<Super>Tab" ];
      cycle-windows-backward = [ "<Shift><Super>Tab" ];
      maximize = [];
      minimize = [ "<Super>Down" ];
      move-to-monitor-down = [];
      move-to-monitor-up = [];
      move-to-workspace-1 = [];
      move-to-workspace-down = [ "<Shift><Super>Down" ];
      move-to-workspace-last = [];
      move-to-workspace-left = [];
      move-to-workspace-right = [];
      move-to-workspace-up = [ "<Shift><Super>Up" ];
      panel-main-menu = [ "<Super>w" ];
      panel-run-dialog = [ "<Super>r" ];
      show-desktop = [ "<Super>d" ];
      switch-applications = [];
      switch-applications-backward = [];
      switch-group = [ "<Alt>grave" ];
      switch-group-backward = [ "<Shift><Alt>grave" "<Shift><Alt>Above_Tab" ];
      switch-panels = [];
      switch-to-workspace-1 = [ "<Super>1" ];
      switch-to-workspace-2 = [ "<Super>2" ];
      switch-to-workspace-3 = [ "<Super>3" ];
      switch-to-workspace-4 = [ "<Super>4" ];
      switch-to-workspace-down = [];
      switch-to-workspace-last = [];
      switch-to-workspace-left = [];
      switch-to-workspace-right = [];
      switch-to-workspace-up = [];
      switch-windows = [ "<Alt>Tab" ];
      switch-windows-backward = [ "<Shift><Alt>Tab" ];
      toggle-fullscreen = [ "<Super>f" ];
      toggle-maximized = [ "<Super>Up" ];
      toggle-shaded = [];
      unmaximize = [];
    };
    "org/gnome/mutter" = {
      overlay-key = "";  # Disable the Meta (Win) key from opening the Activities overview in Gnome Shell.
    };
    "org/gnome/mutter/wayland/keybindings" = {
      restore-shortcuts = [];
    };
    "org/gnome/settings-daemon/plugins/media-keys" = {
      area-screenshot = [ "<Primary>Print" ];
      area-screenshot-clip = [ "<Primary><Shift>Print" ];
      calculator = [ "<Super>a" ];
      decrease-text-size = [ "<Super>KP_Subtract" ];
      home = [ "<Super>e" ];
      increase-text-size = [ "<Super>KP_Add" ];
      logout = [];
      magnifier = [];
      magnifier-zoom-in = [];
      magnifier-zoom-out = [];
      next = [ "AudioNext" ];
      play = [ "AudioPlay" ];
      previous = [ "AudioPrev" ];
      screencast = [];
      screenreader = [ "<Super>q" ];
      screensaver = [];
      screenshot = [];
      screenshot-clip = [ "Print" ];
      terminal = [ "<Super>t" ];
      window-screenshot-clip = [ "<Shift><Alt>Print" ];
      www = [];
    };
    "org/gnome/shell/app-switcher" = {
      current-workspace-only = true;
    };
    "org/gnome/shell/keybindings" = {
      show-screen-recording-ui = [ "<Super>Print" ];
      switch-to-application-1 = [];
      switch-to-application-2 = [];
      switch-to-application-3 = [];
      switch-to-application-4 = [];
      switch-to-application-5 = [];
      switch-to-application-6 = [];
      switch-to-application-7 = [];
      switch-to-application-8 = [];
      switch-to-application-9 = [];
      toggle-application-view = [];
      toggle-message-tray = [ "<Super>x" ];
      toggle-overview = [ "<Super>w" ];
    };
    "org/gnome/shell/overrides" = {
      attach-modal-dialogs = true;
      edge-tiling = false;
      workspaces-only-on-primary = true;
    };
  };
}
