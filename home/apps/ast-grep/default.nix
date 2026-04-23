{ lib, pkgs, ... }:
let
  ast-grep = pkgs.ast-grep;
in
{
  home.packages = [ ast-grep ];

  home.file.".local/bin/sg" = {
    source = "${lib.getExe ast-grep}";
    executable = true;
  };
}
