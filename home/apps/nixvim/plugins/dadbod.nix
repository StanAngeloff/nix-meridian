{ pkgs-unstable, ... }:
{
  programs.nixvim.plugins.vim-dadbod = {
    enable = true;
    package = pkgs-unstable.vimPlugins.vim-dadbod;
  };

  programs.nixvim.plugins.vim-dadbod-ui = {
    enable = true;
    package = pkgs-unstable.vimPlugins.vim-dadbod-ui;
  };

  programs.nixvim.plugins.vim-dadbod-completion = {
    enable = true;
    package = pkgs-unstable.vimPlugins.vim-dadbod-completion;
  };
}
