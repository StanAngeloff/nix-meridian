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
            rev = "985bec8a8ce88fca6f25ea561689485532e24943";
            hash = "sha256-ibhBECZyeGuMuuY6/GZUCa0CZezMLixnLcQ4wNsaRJk=";
          };
        }
      );
    in
    [
      vim-zend55
    ];
}
