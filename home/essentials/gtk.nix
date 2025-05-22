{ config, pkgs, ... }:
with pkgs;
{
  gtk = {
    enable = true;
    theme = {
      name = "adw-gtk3-dark";
      package = adw-gtk3;
    };
    cursorTheme = {
      name = "DMZ-White";
      size = 24;
      package = vanilla-dmz;
    };
    font = {
      name = config.nix-meridian.fonts.sansSerif.name;
      size = 11;
      package = config.nix-meridian.fonts.sansSerif.package;
    };
  };
}
