{ pkgs, ... }:
{
  # This is a documented requirement for appindicator  ¯\_(ツ)_/¯
  services.udev.packages = [ pkgs.gnome-settings-daemon ];
}
