{ pkgs, ... }:
{
  programs.gnome-shell.extensions = with pkgs.gnomeExtensions; [
    {
      # nixpkgs has v84 which caps at Shell 49; v85 adds Shell 50 support
      package = unite.overrideAttrs (prev: {
        version = "85";
        src = prev.src.override {
          rev = "v85";
          hash = "sha256-SN5DYyyZux3jeGgrOc/fd9QcjPRReb2rVZk987saXmQ=";
        };
      });
    }
  ];

  dconf.settings."org/gnome/shell/extensions/unite" = {
    extend-left-box = false;
    hide-activities-button = "never";
    hide-app-menu-icon = false;
    show-desktop-name = false;
    show-legacy-tray = false;
    show-window-buttons = "never";
    show-window-title = "always";
    use-activities-text = false;
  };
}
