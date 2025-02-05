{ config, ... }:
{
  dconf.settings = {
    "org/gnome/desktop/wm/keybindings" = {
      begin-move = [ ];
      begin-resize = [ ];
      cycle-group = [ ];
      cycle-group-backward = [ ];
      cycle-panels = [ ];
      cycle-windows = [ "<Super>Tab" ];
      cycle-windows-backward = [ "<Shift><Super>Tab" ];
      maximize = [ ];
      minimize = [ "<Super>Down" ];
      move-to-monitor-down = [ ];
      move-to-monitor-up = [ ];
      move-to-workspace-1 = [ ];
      move-to-workspace-down = [ "<Shift><Super>Down" ];
      move-to-workspace-last = [ ];
      move-to-workspace-left = [ ];
      move-to-workspace-right = [ ];
      move-to-workspace-up = [ "<Shift><Super>Up" ];
      panel-main-menu = [ "<Super>w" ];
      panel-run-dialog = [ "<Super>r" ];
      show-desktop = [ "<Super>d" ];
      switch-applications = [ ];
      switch-applications-backward = [ ];
      switch-group = [ "<Alt>grave" ];
      switch-group-backward = [
        "<Shift><Alt>grave"
        "<Shift><Alt>Above_Tab"
      ];
      switch-panels = [ ];
      switch-to-workspace-1 = [ "<Super>1" ];
      switch-to-workspace-2 = [ "<Super>2" ];
      switch-to-workspace-3 = [ "<Super>3" ];
      switch-to-workspace-4 = [ "<Super>4" ];
      switch-to-workspace-down = [ ];
      switch-to-workspace-last = [ ];
      switch-to-workspace-left = [ ];
      switch-to-workspace-right = [ ];
      switch-to-workspace-up = [ ];
      switch-windows = [ "<Alt>Tab" ];
      switch-windows-backward = [ "<Shift><Alt>Tab" ];
      toggle-fullscreen = [ "<Super>f" ];
      toggle-maximized = [ "<Super>Up" ];
      toggle-shaded = [ ];
      unmaximize = [ ];
    };
    "org/gnome/mutter" = {
      overlay-key = ""; # Disable the Meta (Win) key from opening the Activities overview in Gnome Shell.
    };
    "org/gnome/mutter/wayland/keybindings" = {
      restore-shortcuts = [ ];
    };
    "org/gnome/settings-daemon/plugins/media-keys" = {
      area-screenshot = [ "<Primary>Print" ];
      area-screenshot-clip = [ "<Primary><Shift>Print" ];
      calculator = [ "<Super>a" ];
      custom-keybindings = [
        "/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom0/"
      ];
      decrease-text-size = [ "<Super>KP_Subtract" ];
      home = [ "<Super>e" ];
      increase-text-size = [ "<Super>KP_Add" ];
      logout = [ ];
      magnifier = [ ];
      magnifier-zoom-in = [ ];
      magnifier-zoom-out = [ ];
      next = [ "AudioNext" ];
      play = [ "AudioPlay" ];
      previous = [ "AudioPrev" ];
      screencast = [ ];
      screenreader = [ "<Super>q" ];
      screensaver = [ ];
      screenshot = [ ];
      screenshot-clip = [ "Print" ];
      terminal = [ "<Super>t" ];
      window-screenshot-clip = [ "<Shift><Alt>Print" ];
      www = [ ];
    };
    "org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom0" = {
      binding = "<Super>t";
      command = "${config.home.homeDirectory}/.local/bin/launch-alacritty";
      name = "Alacritty";
    };
    "org/gnome/shell/keybindings" = {
      show-screen-recording-ui = [ "<Super>Print" ];
      switch-to-application-1 = [ ];
      switch-to-application-2 = [ ];
      switch-to-application-3 = [ ];
      switch-to-application-4 = [ ];
      switch-to-application-5 = [ ];
      switch-to-application-6 = [ ];
      switch-to-application-7 = [ ];
      switch-to-application-8 = [ ];
      switch-to-application-9 = [ ];
      toggle-application-view = [ ];
      toggle-message-tray = [ "<Super>x" ];
      toggle-overview = [ "<Super>w" ];
    };
  };
}
