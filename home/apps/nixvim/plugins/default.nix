{ pkgs, ... }:
let
  vim-zend55 = (
    pkgs.vimUtils.buildVimPlugin {
      name = "vim-zend55";
      src = pkgs.fetchFromGitHub {
        owner = "StanAngeloff";
        repo = "vim-zend55";
        rev = "12a7a992ac75c49d1275325bcded5c6c33069ae6";
        hash = "sha256-jhcjA1IsxBr3c0QOSFWA4bBTX1Y6ITGjlwg6Lnz5GxA=";
      };
    }
  );
in
{
  imports = [
    ./copilot.nix
    ./fzf.nix
    ./gitgutter.nix
    ./lsp.nix
    ./nerdtree.nix
    ./ripgrep.nix
    ./surround.nix
    ./tree-sitter.nix
  ];

  programs.nixvim = {
    extraPlugins = [
      vim-zend55
    ];
  };
}
