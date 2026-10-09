{
  config,
  lib,
  pkgs,
  pkgs-unstable,
  ...
}:
let
  segoe-ui-variable = pkgs.callPackage ./fonts/segoe-ui-variable/package.nix { };

  # The system fonts' cache in the format nixpkgs-unstable's fontconfig reads, beside the one NixOS builds with the system's.
  # Programs from nixpkgs-unstable (its Electron: Plannotator's review window, Proton Pass) link a fontconfig whose cache format
  # is newer, so NixOS's cache is invisible to them and they rescan every font directory.
  unstableFontsCache = pkgs.makeFontsCache {
    inherit (pkgs-unstable) fontconfig;
    fontDirectories = config.fonts.packages;
  };
in
{
  fonts = {
    enableDefaultPackages = true;

    packages =
      with lib;
      with pkgs;
      let
        optionalPackage = font: optional (font != null && font.package != null) font.package;
      in
      unique (
        [
          corefonts # Microsoft's TrueType core fonts for the Web
          vista-fonts # TrueType fonts from Microsoft Windows Vista (Calibri, Cambria, Candara, Consolas, Constantia, Corbel)
          openmoji-color
          segoe-ui-variable
        ]
        ++ concatMap optionalPackage [
          config.nix-meridian.fonts.sansSerif
          config.nix-meridian.fonts.serif
          config.nix-meridian.fonts.monospace
        ]
      );

    fontconfig = {
      enable = true;

      subpixel.rgba = "rgb";

      # This would ideally be done in Home Manager, however it lacks the option to add extra configuration.
      # A whole document: local.conf is read as a file of its own, and a second root element breaks all of it.
      localConf = ''
        <?xml version="1.0"?>
        <!DOCTYPE fontconfig SYSTEM "urn:fontconfig:fonts.dtd">
        <fontconfig>
          <alias>
            <family>Segoe UI</family>
            <prefer>
              <family>Segoe UI Variable</family>
            </prefer>
          </alias>
          <cachedir>${unstableFontsCache}</cachedir>
        </fontconfig>
      '';
    };
  };
}
