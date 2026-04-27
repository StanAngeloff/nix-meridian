{ lib, pkgs, ... }:
{
  home.packages = with pkgs; [
    eog
  ];

  home.file = {
    ".local/share/eog/plugins/swappy/swappy.plugin".source = ./plugin/swappy.plugin;
    ".local/share/eog/plugins/swappy/swappy.py".text =
      builtins.replaceStrings [ "@swappy@" ] [ (lib.getExe pkgs.swappy) ]
        (builtins.readFile ./plugin/swappy.py);
  };

  dconf.settings = {
    "org/gnome/eog/plugins" = {
      active-plugins = [
        "fullscreen"
        "swappy"
      ];
    };
  };
}
