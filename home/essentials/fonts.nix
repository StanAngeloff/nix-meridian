{ config, ... }:
{
  fonts.fontconfig = {
    # NOTE: This is the setting for Home Manager to allow fontconfig to discover fonts
    #       and configurations installed through **home.packages** and `nix-env`.
    enable = true;

    defaultFonts = {
      sansSerif = [ config.meridian.fonts.sansSerifFontFamily ];
      serif = [ config.meridian.fonts.serifFontFamily ];
      monospace = [ config.meridian.fonts.monospaceFontFamily ];
    };
  };

  dconf.settings = {
    "org/gnome/desktop/interface" = {
      font-hinting = "full";
      font-antialiasing = "rgba";
      font-name = "${config.meridian.fonts.sansSerifFontFamily} 11";
      document-font-name = "${config.meridian.fonts.sansSerifFontFamily} 11";
      monospace-font-name = "${config.meridian.fonts.monospaceFontFamily} 11";
    };
    "org/gnome/desktop/wm/preferences" = {
      titlebar-uses-system-font = true;
    };
  };
}
