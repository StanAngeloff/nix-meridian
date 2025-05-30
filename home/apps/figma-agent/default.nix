{ pkgs, ... }:
let
  package = pkgs.callPackage ./package.nix { };
in
{
  home.packages = [ package ];

  systemd.user.targets.graphical-session.Unit.Wants = [ "figma-agent.service" ];
}
