{ pkgs, ... }:
{
  programs.nixvim.extraPlugins = let
    vim-zend55 = (
      pkgs.vimUtils.buildVimPlugin {
        name = "vim-zend55";
        src = pkgs.fetchFromGitHub {
          owner = "StanAngeloff";
          repo = "vim-zend55";
          rev = "d1b6c5206762f3aacf044c6210374c5c300a6ece";
          hash = "sha256-hbiNcxwa9zQlmPWq1fclgIN4p0i03xpCbB1r8vwgpYA=";
        };
      }
    );
  in [
    vim-zend55
  ];
}
