{ pkgs, ... }:
let
  vim-fugitive-blame-ext = (
    pkgs.vimUtils.buildVimPlugin {
      name = "vim-fugitive-blame-ext";
      src = pkgs.fetchFromGitHub {
        owner = "tommcdo";
        repo = "vim-fugitive-blame-ext";
        rev = "0c9355deeb235f89f50e3e9f362469826efcfb6a";
        hash = "sha256-ELUVZJUqN23Z6/HS1Er/Lxuh5X2aFx81PiQ7cxItsJA=";
      };
    }
  );
in
{
  programs.nixvim.plugins.fugitive = {
    enable = true;
  };

  programs.nixvim.extraPlugins = [
    vim-fugitive-blame-ext
  ];
}
