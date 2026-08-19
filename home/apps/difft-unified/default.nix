{
  lib,
  pkgs,
  ...
}:
let
  difft-unified = pkgs.callPackage ./package.nix { };
in
{
  home.packages = [
    difft-unified
    difft-unified.pager
  ];

  programs.git = {
    settings = {
      alias = {
        dft = "!git -c diff.external=${lib.getExe difft-unified} -c pager.diff=${lib.getExe difft-unified.pager} diff";
      };
    };
  };
}
