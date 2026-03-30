{ pkgs, ... }:
let
  voxize = pkgs.callPackage ./package.nix { };
in
{
  home.packages = [
    voxize
  ];
}
