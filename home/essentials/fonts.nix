{ pkgs, ... }:
{
  # NOTE: This is the setting for Home Manager to allow fontconfig to discover fonts
  #       and configurations installed through **home.packages** and `nix-env`.
  fonts.fontconfig.enable = true;

  home.packages = with pkgs; [
    ibm-plex
  ];

  dconf.settings = {
    "org/gnome/desktop/interface" = {
      font-hinting = "full";
      font-antialiasing = "rgba";
      font-name = "IBM Plex Sans 11";
      document-font-name = "IBM Plex Sans 11";
      monospace-font-name = "Berkeley Mono 11";
    };
    "org/gnome/desktop/wm/preferences" = {
      titlebar-uses-system-font = true;
    };
  };
}
