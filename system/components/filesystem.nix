{ lib, ... }:
let
  paths = [
    "/data/projects/github.com/"
    "/data/public/github.com/"
  ];

  pathUtils = import ../../modules/lib/path-utils.nix { inherit lib; };
in
{
  boot.tmp = {
    # /tmp is on disk rather than in RAM: most of what lands in /tmp is build-tool caches, gigabytes of them between reboots,
    # while browsers keep their caches in ~/.cache.
    #
    # Emptied at every boot.
    cleanOnBoot = true;
  };

  services.locate.enable = true;

  systemd.tmpfiles.rules = map (path: "d \"${path}\" 0755 stan users -") (
    pathUtils.collectPaths paths
  );
}
