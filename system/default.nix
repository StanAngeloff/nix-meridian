{ pkgs, ... }:
{
  imports = [
    ./apps
    ./essentials
  ];

  programs.nix-ld.enable = true;

  # Electron and Chromium
  environment.sessionVariables.NIXOS_OZONE_WL = "1";

  # Some programs need SUID wrappers, can be configured further or are
  # started in user sessions.
  # programs.mtr.enable = true;
  # programs.gnupg.agent = {
  #   enable = true;
  #   enableSSHSupport = true;
  # };

  # Make Zsh the default on a system level.
  programs.zsh = { enable = true; };
  users.defaultUserShell = pkgs.zsh;
  environment.shells = [pkgs.zsh];
}
