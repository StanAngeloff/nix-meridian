{ pkgs, ... }:
{
  programs.nixvim = {
    extraPlugins = with pkgs.vimPlugins; [
      vim-asterisk
    ];

    extraConfigVim = ''
      map *  <Plug>(asterisk-z*)
      map #  <Plug>(asterisk-z#)
      map g* <Plug>(asterisk-gz*)
      map g# <Plug>(asterisk-gz#)
    '';
  };
}
