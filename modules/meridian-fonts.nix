{ lib, ... }:
with lib;
{
  options.meridian.fonts = {
    sansSerifFontFamily = mkOption {
      default = "IBM Plex Sans";
      description = "The system-wide default sans-serif font family.";
      type = types.str;
    };

    serifFontFamily = mkOption {
      default = "IBM Plex Serif";
      description = "The system-wide default serif font family.";
      type = types.str;
    };

    monospaceFontFamily = mkOption {
      default = "Berkeley Mono";
      description = "The system-wide default monospace font family.";
      type = types.str;
    };
  };
}
