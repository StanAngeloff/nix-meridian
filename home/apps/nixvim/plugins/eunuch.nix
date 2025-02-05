{ pkgs, ... }:
{
  programs.nixvim.extraPlugins =
    let
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
    in
    [
      vim-eunuch
    ];
}
