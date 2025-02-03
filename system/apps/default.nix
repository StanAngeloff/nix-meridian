{ pkgs, ... }:
{
  # Allow unfree packages
  nixpkgs.config.allowUnfree = true;

  environment.systemPackages = with pkgs; [
    emote
    gnome-tweaks
    google-chrome
    slack
  ];

  # Sushi, a quick previewer for Nautilus.
  services.gnome.sushi.enable = true;

  environment.variables = {
    # See https://wiki.archlinux.org/title/GNOME/Tips_and_tricks#Set_slow_down_factor
    # See https://github.com/GNOME/gnome-shell/blob/42.9/js/ui/environment.js#L468 -- the value MUST be greater than 0.
    GNOME_SHELL_SLOWDOWN_FACTOR = "0.00000001";
  };
}
