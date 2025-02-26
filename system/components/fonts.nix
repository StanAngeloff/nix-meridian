{
  config,
  lib,
  pkgs,
  ...
}:
let
  segoe-ui-variable = import ./fonts/segoe-ui-variable.nix { inherit lib pkgs; };
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
          vistafonts # TrueType fonts from Microsoft Windows Vista (Calibri, Cambria, Candara, Consolas, Constantia, Corbel)
          segoe-ui-variable.package
        ]
        ++ concatMap optionalPackage [
          config.nix-meridian.fonts.sansSerif
          config.nix-meridian.fonts.serif
          config.nix-meridian.fonts.monospace
        ]
      );

    fontconfig = {
      enable = true;

      # This would ideally be done in Home Manager, however it lacks the option to add extra configuration.
      localConf = ''
        <alias>
          <family>Segoe UI</family>
          <prefer>
            <family>Segoe UI Variable</family>
          </prefer>
        </alias>
      '';
    };
  };
}
