{ pkgs, ... }:
{
  programs.gnome-shell.extensions = with pkgs.gnomeExtensions; [
    { package = bluetooth-battery-meter; }
  ];

  dconf.settings."org/gnome/shell/extensions/Bluetooth-Battery-Meter" = {
    enable-battery-level-text = true;
  };
}
