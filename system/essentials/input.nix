{ pkgs, ... }:
{
  # Configure keymap in X11
  services.xserver.xkb = {
    layout = "us";
    variant = "";
  };

  # Enable Ctrl+Shift+U to input unicode characters in X11.
  i18n.inputMethod = {
    enable = true;
    type = "ibus";
    ibus.engines = with pkgs.ibus-engines; [ ];
  };

  # Enable touchpad support (enabled default in most desktopManager).
  services.libinput.enable = true;
}
