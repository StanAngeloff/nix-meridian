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
    useZram = true;
    zramSettings = {
      zram-size = "min(ram / 2, 8192)";
      compression-algorithm = "lzo-rle";
    };
  };

  services.locate.enable = true;

  systemd.tmpfiles.rules = map (path: "d \"${path}\" 0755 stan users -") (
    pathUtils.collectPaths paths
  );
}
