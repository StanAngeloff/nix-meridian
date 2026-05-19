{ pkgs, ... }:
{
  home.packages = [
    pkgs.httpie

    (pkgs.callPackage ./curl2httpie/package.nix {
      inherit (pkgs) curlconverter;
    })
  ];
}
