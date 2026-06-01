{ pkgs, ... }:
let
  nodejs = pkgs.nodejs_24;
  pnpm = pkgs.pnpm.override { inherit nodejs; };
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
