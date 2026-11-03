{ lib, pkgs, ... }:
{
  home.packages = with pkgs; [
    eog
  ];

  # One read-only store directory, so Python can't write a __pycache__ beside the plugin.
  # Store files all have mtime 1 and a new swappy path keeps the size, so a cached .pyc would never be invalidated.
  home.file.".local/share/eog/plugins/swappy".source = pkgs.linkFarm "eog-plugin-swappy" {
    "swappy.plugin" = ./plugin/swappy.plugin;
    "swappy.py" = pkgs.replaceVars ./plugin/swappy.py { swappy = lib.getExe pkgs.swappy; };
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
