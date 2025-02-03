{ pkgs, ... }:
{
  imports = [
    ./copilot.nix
    ./fugitive.nix
    ./fzf.nix
    ./gitgutter.nix
    ./lsp.nix
    ./nerdtree.nix
    ./nvim-autopairs.nix
    ./repeat.nix
    ./ripgrep.nix
    ./sleuth.nix
    ./surround.nix
    ./tree-sitter.nix
    ./undotree.nix
  ];

  programs.nixvim = let
    vim-zend55 = (
      pkgs.vimUtils.buildVimPlugin {
        name = "vim-zend55";
        src = pkgs.fetchFromGitHub {
          owner = "StanAngeloff";
          repo = "vim-zend55";
          rev = "42cc5d985e58462f801a20abdaf7aa99b395dce8";
          hash = "sha256-E0/yJp669nHWxHstSKN8iNdiDiPxUJt5669w54nmUBo=";
        };
      }
    );
    vim-eunuch = (
      pkgs.vimUtils.buildVimPlugin {
        name = "vim-eunuch";
        src = pkgs.fetchFromGitHub {
          owner = "tpope";
          repo = "vim-eunuch";
          rev = "e86bb794a1c10a2edac130feb0ea590a00d03f1e";
          hash = "sha256-vvt9CJfD2Y8rhFKVbvSEJYQN8jWrw6NTq8Wp/COVH1E=";
        };
      }
    );
  in {
    extraPlugins = [
      vim-zend55
      vim-eunuch
    ];
  };
}
