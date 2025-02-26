{ lib, pkgs, ... }:
with lib;
{
  options.nix-meridian.fonts = {
    sansSerif = {
      name = mkOption {
        default = "IBM Plex Sans";
        description = "The system-wide default sans-serif font family.";
        type = types.str;
      };
      package = mkOption {
        type = types.nullOr types.package;
        example = literalExpression "pkgs.ibm-plex";
        default = pkgs.ibm-plex;
      };
    };

    serif = {
      name = mkOption {
        default = "IBM Plex Serif";
        description = "The system-wide default serif font family.";
        type = types.str;
      };
      package = mkOption {
        type = types.nullOr types.package;
        example = literalExpression "pkgs.ibm-plex";
        default = pkgs.ibm-plex;
      };
    };

    monospace = {
      name = mkOption {
        default = "Berkeley Mono";
        description = "The system-wide default monospace font family.";
        type = types.str;
      };
      package = mkOption {
        type = types.nullOr types.package;
        example = literalExpression "pkgs.ibm-plex";
        default = null;
      };
    };
  };
}
