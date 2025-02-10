{ pkgs, ... }:
{
  programs.gnome-shell.extensions = with pkgs.gnomeExtensions; [
    { package = bing-wallpaper-changer; }
  ];

  dconf.settings."org/gnome/shell/extensions/bingwallpaper" = {
    delete-previous = true;
    market = "en-GB";
  };
}
