{ pkgs, ... }:
let
  nodejs = pkgs.nodejs_24;
in
{
  home.packages = [
    pkgs.httpie

    (pkgs.callPackage ./curl2httpie/package.nix {
      pnpm = nodejs.pkgs.pnpm;
    })
  ];
}
