{ lib, pkgs, ... }:
let
  segoe-ui-variable = import ./fonts/segoe-ui-variable.nix { inherit lib pkgs; };

  sansSerifFontFamily = "IBM Plex Sans";
  serifFontFamily = "IBM Plex Serif";
  monospaceFontFamily = "Berkeley Mono";
in
{
  fonts.fontconfig = {
    # NOTE: This is the setting for Home Manager to allow fontconfig to discover fonts
    #       and configurations installed through **home.packages** and `nix-env`.
    enable = true;

    defaultFonts = {
      sansSerif = [ sansSerifFontFamily ];
      serif = [ serifFontFamily ];
      monospace = [ monospaceFontFamily ];
    };
  };

  home.packages = with pkgs; [
    ibm-plex

    corefonts # Microsoft's TrueType core fonts for the Web
    vistafonts # TrueType fonts from Microsoft Windows Vista (Calibri, Cambria, Candara, Consolas, Constantia, Corbel)
    segoe-ui-variable.package
  ];

  dconf.settings = {
    "org/gnome/desktop/interface" = {
      font-hinting = "full";
      font-antialiasing = "rgba";
      font-name = "${sansSerifFontFamily} 11";
      document-font-name = "${sansSerifFontFamily} 11";
      monospace-font-name = "${monospaceFontFamily} 11";
    };
    "org/gnome/desktop/wm/preferences" = {
      titlebar-uses-system-font = true;
    };
  };
}
