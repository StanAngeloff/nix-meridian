{ config, pkgs, ... }:
{
  home.packages = with pkgs; [ tig ];

  home.file."${config.home.homeDirectory}/.config/tig/config".source = ./tigrc;
  home.file."${config.home.homeDirectory}/.config/tig/vim.tigrc".source = ./vim.tigrc;
}
