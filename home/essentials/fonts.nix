{ config, ... }:
{
  fonts.fontconfig = {
    # NOTE: This is the setting for Home Manager to allow fontconfig to discover fonts
    #       and configurations installed through **home.packages** and `nix-env`.
    enable = true;

    defaultFonts = {
      sansSerif = [ config.nix-meridian.fonts.sansSerifFontFamily ];
      serif = [ config.nix-meridian.fonts.serifFontFamily ];
      monospace = [ config.nix-meridian.fonts.monospaceFontFamily ];
    };
  };

  dconf.settings = {
    "org/gnome/desktop/interface" = {
      font-hinting = "full";
      font-antialiasing = "rgba";
      font-name = "${config.nix-meridian.fonts.sansSerifFontFamily} 11";
      document-font-name = "${config.nix-meridian.fonts.sansSerifFontFamily} 11";
      monospace-font-name = "${config.nix-meridian.fonts.monospaceFontFamily} 11";
    };
    "org/gnome/desktop/wm/preferences" = {
      titlebar-uses-system-font = true;
    };
  };
}
