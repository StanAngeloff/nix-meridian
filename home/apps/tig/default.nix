{
  lib,
  pkgs,
  pkgs-unstable,
  ...
}:
let
  tig = pkgs-unstable.tig;
  ansiless = cmd: "${lib.getExe pkgs.perl} -pe 's/\\e\\[[0-9;]*m//g' | ${cmd}";
in
{
  home.packages = [
    tig
  ];

  home.file.".config/tig/config".source = ./tigrc;
  home.file.".config/tig/vim.tigrc".source = ./vim.tigrc;

  programs.git = {
    settings = {
      pager = {
        diff = ansiless (lib.getExe tig);
        show = ansiless (lib.getExe tig);
      };
    };
  };
}
