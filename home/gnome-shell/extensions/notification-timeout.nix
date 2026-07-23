{ pkgs, ... }:
{
  # Fixes GNOME's idle-gated notification banners: by default a banner only times out while the user is active (idle time under 1 second), so otherwise it stays on screen until the next key press or mouse move and later notifications queue up behind it, appearing one-behind. This extension forces messageTray's _userActiveWhileNotificationShown flag true so banners always time out. See https://extensions.gnome.org/extension/3795/notification-timeout/.
  programs.gnome-shell.extensions = with pkgs.gnomeExtensions; [
    { package = notification-timeout; }
  ];

  dconf.settings."org/gnome/shell/extensions/notification-timeout" = {
    ignore-idle = true; # time notifications out even when the user is idle (the actual fix)
    always-normal = false; # keep critical and urgent notifications sticky instead of downgrading them to normal
    timeout = 4000; # banner display time in milliseconds, matching GNOME's native normal-notification duration
  };
}
