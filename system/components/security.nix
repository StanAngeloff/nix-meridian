{ lib, pkgs, ... }:
{
  security.sudo = {
    extraConfig = ''
      # Prompt for a password on every escalation.
      Defaults	timestamp_timeout=0
    '';

    extraRules = [
      {
        users = [ "stan" ];
        runAs = "ALL:ALL";
        commands = [
          # nixfmt: off
          # Allow `nh switch` to activate a new configuration without a password.
          { command = "/run/current-system/sw/bin/env * /nix/store/*-nixos-system-*/bin/switch-to-configuration test"; options = [ "NOPASSWD" ]; }
          { command = "/run/current-system/sw/bin/env * nix build --no-link --profile /nix/var/nix/profiles/system /nix/store/*-nixos-system-*"; options = [ "NOPASSWD" ]; }
          { command = "/run/current-system/sw/bin/env * /nix/store/*-nixos-system-*/bin/switch-to-configuration boot"; options = [ "NOPASSWD" ]; }
          # nixfmt: on
        ];
      }
    ];
  };

  # Learn more at https://discourse.nixos.org/t/ssl-cert-file-and-connection-issues-in-nix-shells/7856
  environment.sessionVariables.SSL_CERT_FILE = "${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt";

  services.fprintd = {
    enable = lib.mkDefault false;
  };
}
