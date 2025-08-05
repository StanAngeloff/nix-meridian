{ voxinput-pkgs, pkgs, ... }:
let
  voxinput = pkgs.callPackage ./package.nix {
    voxinput = voxinput-pkgs.default;
  };
in
{
  home.packages = [
    voxinput
  ];
}
