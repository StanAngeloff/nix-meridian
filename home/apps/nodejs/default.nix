{ pkgs, ... }:
let
  nodejs = pkgs.nodejs_24;
in
{
  home.packages = [
    nodejs
    nodejs.pkgs.pnpm
  ];

  home.file.".config/pnpm/rc".text = ''
    engine-strict=false
    package-manager-strict-version=false
  '';
}
