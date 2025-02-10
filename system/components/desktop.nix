{ pkgs, ... }:
{
  # Enable the X11 windowing system.
  services.xserver.enable = true;

  # Enable the GNOME Desktop Environment.
  services.xserver.displayManager.gdm.enable = true;
  services.xserver.desktopManager.gnome = {
    enable = true;
    extraGSettingsOverridePackages = [ pkgs.mutter ];
    extraGSettingsOverrides = ''
      [org.gnome.mutter]
      experimental-features=['scale-monitor-framebuffer']
    '';
  };

  # Enable automatic login for the user.
  services.displayManager.autoLogin = {
    enable = true;
    user = "stan";
  };

  # Workaround for GNOME autologin: https://github.com/NixOS/nixpkgs/issues/103746#issuecomment-945091229
  systemd.services."getty@tty1".enable = false;
  systemd.services."autovt@tty1".enable = false;

  # Automatically unlock the GNOME keyring on login.
  services.gnome.gnome-keyring.enable = true;
  security.pam.services.login.enableGnomeKeyring = true;

  # Sushi, a quick previewer for Nautilus.
  services.gnome.sushi.enable = true;

  # Electron and Chromium
  environment.sessionVariables.NIXOS_OZONE_WL = "1";

  # See https://wiki.archlinux.org/title/GNOME/Tips_and_tricks#Set_slow_down_factor
  # See https://github.com/GNOME/gnome-shell/blob/42.9/js/ui/environment.js#L468 -- the value MUST be greater than 0.
  environment.variables.GNOME_SHELL_SLOWDOWN_FACTOR = "0.00000001";
}
