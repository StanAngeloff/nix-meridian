{ pkgs, ... }:
{
  security.sudo = {
    extraConfig = ''
      # Prompt for a password on every escalation.
      Defaults	timestamp_timeout=0
    '';

    extraRules = [
      # Allow nixos-rebuild to run without a password.
      {
        users = [ "stan" ];
        runAs = "ALL:ALL";
        commands = [
          {
            command = "/run/current-system/sw/bin/nixos-rebuild";
            options = [ "NOPASSWD" ];
          }
        ];
      }
    ];
  };

  # Learn more at https://discourse.nixos.org/t/ssl-cert-file-and-connection-issues-in-nix-shells/7856
  environment.sessionVariables.SSL_CERT_FILE = "${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt";

  services.fprintd = {
    # > Broadcom has not provided Linux drivers for the fingerprint reader [..]
    #
    # Learn more at https://wiki.nixos.org/wiki/Hardware/Dell/Latitude_E7240
    enable = false;

    #tod = {
    #  enable = true;
    #};
  };
}
