{ pkgs, ... }:
let
  nodejs = pkgs.nodejs_24;
  pnpm = pkgs.pnpm.override { nodejs-slim = nodejs; };
in
{
  home.packages = [
    nodejs
    pnpm
  ];

  home.file.".config/pnpm/rc".text = ''
    engine-strict=false
    package-manager-strict-version=false
  '';
}
