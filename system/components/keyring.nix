{
  services.gnome.gnome-keyring = {
    enable = true;
  };

  # NOTE: This is currently broken on NixOS when using LUKS and GDM auto-login.
  #       Learn more at https://github.com/NixOS/nixpkgs/pull/286587 which will introduce a fix using `pam_systemd_loadkey`.
  #security.pam.services.gdm-password = {
  #  enableGnomeKeyring = true;
  #};
}
