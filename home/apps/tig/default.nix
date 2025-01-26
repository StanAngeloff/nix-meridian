{ pkgs, ... }:
{
  home.packages = with pkgs; [ tig ];

  home.file.".tigrc".source = ./tigrc;
  home.file.".tigrc.vim".source = ./vim.tigrc;
}
