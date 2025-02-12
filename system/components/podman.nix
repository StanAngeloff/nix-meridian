{ pkgs, ... }:
{
  virtualisation = {
    containers = {
      enable = true;

      containersConf.settings.engine = {
        compose_providers = [ "${pkgs.docker-compose}/bin/docker-compose" ];
        compose_warning_logs = false;
      };
    };

    podman = {
      enable = true;
      dockerCompat = true;
      dockerSocket.enable = true;

      defaultNetwork.settings.dns_enabled = true;
    };
  };

  environment.systemPackages = with pkgs; [
    docker-compose
  ];
}
