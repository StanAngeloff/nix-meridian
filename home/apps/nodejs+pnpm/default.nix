{ config, pkgs, ... }:
let
  nodejs = pkgs.nodejs_22;
in
{
  home.packages = [
    nodejs
    nodejs.pkgs.pnpm
  ];

  home.file."${config.home.homeDirectory}/.config/pnpm/rc".text = ''
    engine-strict=false
    package-manager-strict-version=false
  '';
}
