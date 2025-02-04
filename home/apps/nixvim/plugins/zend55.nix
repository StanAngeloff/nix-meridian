{ pkgs, ... }:
{
  programs.nixvim.extraPlugins = let
    vim-zend55 = (
      pkgs.vimUtils.buildVimPlugin {
        name = "vim-zend55";
        src = pkgs.fetchFromGitHub {
          owner = "StanAngeloff";
          repo = "vim-zend55";
          rev = "3c1656c747900cafe781d30714fb7782111ca3ba";
          hash = "sha256-oA+LNgm5ggOMn8SclXN+kgqdnXA508oIbC/8zCuc2uc=";
        };
      }
    );
  in [
    vim-zend55
  ];
}
