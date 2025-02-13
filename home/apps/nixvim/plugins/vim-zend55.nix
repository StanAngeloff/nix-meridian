{ pkgs, ... }:
{
  programs.nixvim.extraPlugins =
    let
      vim-zend55 = (
        pkgs.vimUtils.buildVimPlugin {
          name = "vim-zend55";
          src = pkgs.fetchFromGitHub {
            owner = "StanAngeloff";
            repo = "vim-zend55";
            rev = "ff39ee66b11a07a00980e6a7f15f811408542f65";
            hash = "sha256-nIbhCIeMIeUiij++N3Wkq8ZYKxI6TC2+9wu3BOg97a0=";
          };
        }
      );
    in
    [
      vim-zend55
    ];
}
