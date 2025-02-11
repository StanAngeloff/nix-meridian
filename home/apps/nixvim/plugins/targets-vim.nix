{ pkgs, ... }:
{
  programs.nixvim = {
    extraPlugins =
      let
        targets = (
          pkgs.vimUtils.buildVimPlugin {
            name = "targets.vim";
            src = pkgs.fetchFromGitHub {
              owner = "wellle";
              repo = "targets.vim";
              rev = "6325416da8f89992b005db3e4517aaef0242602e";
              hash = "sha256-ThfL4J/r8Mr9WemSUwIea8gsolSX9gabJ6T0XYgAaE4=";
            };
          }
        );
      in
      [
        targets
      ];
  };
}
