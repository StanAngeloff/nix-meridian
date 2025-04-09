{ pkgs-unstable, ... }:
{
  programs.nixvim = {
    extraPlugins = with pkgs-unstable.vimPlugins; [
      copilot-lualine
    ];
  };
}
