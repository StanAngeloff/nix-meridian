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
      # NOTE: $DOCKER_HOST is preferred over the socket which is created as `root`.
      #dockerSocket = {
      #  enable = true;
      #};

      defaultNetwork = {
        settings = {
          dns_enabled = true;
        };
      };
    };
  };

  environment.systemPackages = with pkgs; [
    docker-compose
  ];

  environment.sessionVariables.DOCKER_HOST = "unix://$XDG_RUNTIME_DIR/podman/podman.sock";
}
