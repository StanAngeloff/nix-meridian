{ voxinput-pkgs, pkgs, ... }:
let
  voxinput = pkgs.callPackage ./package.nix {
    voxinput = voxinput-pkgs.default;
  };
  voxinput-record = pkgs.callPackage ./record/package.nix {
    inherit voxinput;
  };
in
{
  home.packages = [
    voxinput
    voxinput-record
  ];
}
