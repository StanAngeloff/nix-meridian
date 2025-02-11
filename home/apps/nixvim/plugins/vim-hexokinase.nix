{ pkgs, ... }:
{
  programs.nixvim = {
    extraPlugins = with pkgs.vimPlugins; [
      vim-hexokinase
    ];

    globals = {
      Hexokinase_highlighters = [ "backgroundfull" ];
    };
  };
}
