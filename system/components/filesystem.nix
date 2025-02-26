{ lib, ... }:
let
  paths = [
    "/data/projects/github.com/"
    "/data/public/github.com/"
  ];

  pathUtils = import ../../modules/lib/path-utils.nix { inherit lib; };
in
{
  systemd.tmpfiles.rules = map (path: "d \"${path}\" 0755 stan users -") (
    pathUtils.collectPaths paths
  );
}
