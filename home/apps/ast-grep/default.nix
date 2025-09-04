{ lib, pkgs-unstable, ... }:
let
  ast-grep = pkgs-unstable.ast-grep;
in
{
  home.packages = [ ast-grep ];

  home.file.".local/bin/sg" = {
    executable = true;
    text = ''
      #!/bin/sh
      exec "${lib.getExe ast-grep}" "$@"
    '';
  };
}
