{ pkgs, ... }:
{
  programs.nixvim = {
    plugins.web-devicons = {
      enable = true;
    };

    extraPlugins = with pkgs.vimPlugins; [
      vim-devicons # This is technically unrelated to web-devicons, however it adds file type icons to Vim plugins, such as NERDTree.
    ];
  };
}
