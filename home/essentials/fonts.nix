{
  config,
  pkgs,
  pkgs-unstable,
  ...
}:
let
  # The profile fonts' cache for nixpkgs-unstable's fontconfig, beside the one Home Manager builds;
  # see unstableFontsCache in system/components/fonts.nix.
  unstableFontsCache = pkgs.makeFontsCache {
    inherit (pkgs-unstable) fontconfig;
    fontDirectories = [
      "${config.home.path}/lib/X11/fonts"
      "${config.home.path}/share/fonts"
    ];
  };
in
{
  fonts.fontconfig = {
    # NOTE: This is the setting for Home Manager to allow fontconfig to discover fonts
    #       and configurations installed through **home.packages** and `nix-env`.
    enable = true;

    configFile.fonts-unstable-cache = {
      enable = true;
      # Beside Home Manager's own 10-hm-fonts.conf.
      priority = 10;
      text = ''
        <?xml version='1.0'?>
        <!DOCTYPE fontconfig SYSTEM 'urn:fontconfig:fonts.dtd'>
        <fontconfig>
          <cachedir>${unstableFontsCache}</cachedir>
        </fontconfig>
      '';
    };

    defaultFonts = {
      sansSerif = [ config.nix-meridian.fonts.sansSerif.name ];
      serif = [ config.nix-meridian.fonts.serif.name ];
      monospace = [ config.nix-meridian.fonts.monospace.name ];
      emoji = [
        "Noto Color Emoji"
        "OpenMoji Color" # Fallback when Noto Color Emoji doesn't have the glyph or for apps blocked from using Noto Color Emoji (e.g., Viber)
      ];
    };
  };

  dconf.settings = {
    "org/gnome/desktop/interface" = {
      font-hinting = "full";
      font-antialiasing = "rgba";
      document-font-name = "${config.nix-meridian.fonts.sansSerif.name} 11";
      monospace-font-name = "${config.nix-meridian.fonts.monospace.name} 11";
      # See ./gtk.nix
      #font-name = "${config.nix-meridian.fonts.sansSerif.name} 11";
    };
    "org/gnome/desktop/wm/preferences" = {
      titlebar-uses-system-font = true;
    };
  };
}
