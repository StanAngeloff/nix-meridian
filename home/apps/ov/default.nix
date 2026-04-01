{ lib, pkgs-unstable, ... }:
let
  ov = pkgs-unstable.ov;
in
{
  home.packages = [
    ov
  ];

  home.file.".config/ov/config.yml".source = ./ov-less.yaml;

  programs.git = {
    iniContent = {
      core.pager = "${ov}/bin/ov ${lib.escapeShellArgs [ "--quit-if-one-screen" ]}";
    };
  };
}
