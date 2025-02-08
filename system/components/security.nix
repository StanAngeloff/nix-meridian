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
}
