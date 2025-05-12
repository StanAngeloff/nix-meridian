{ config, pkgs, ... }:
let
  nixvim = config.lib.nixvim;
  claudius-settings = {
    parameters = {
      max_tokens = 8000;
    };
    editing = {
      auto_write = true;
    };
    pricing = {
      enabled = true;
    };
    ruler = {
      char = "━";
    };
    signs = {
      enabled = true;
      assistant = {
        hl = "#8f9fdf";
      };
      user = {
        char = "▏";
        hl = "#6f6f6f";
      };
    };
    highlights = {
      assistant = "#8f9faf";
    };
  };
in
{
  programs.nixvim = {
    extraPlugins =
      let
        claudius-nvim = (
          pkgs.vimUtils.buildVimPlugin {
            name = "claudius.nvim";
            src = pkgs.fetchFromGitHub {
              owner = "StanAngeloff";
              repo = "claudius.nvim";
              rev = "d47139e60d72509665d81d3d0f409fa460c7c50f";
              hash = "sha256-yEIFHz/Gku0aQtTiQbX1ynVey31868b07az2O9X3oqM=";
            };
          }
        );
      in
      [
        claudius-nvim
      ];

    extraConfigLua = ''
      require("claudius").setup(${nixvim.toLuaObject claudius-settings});
    '';
  };
}
