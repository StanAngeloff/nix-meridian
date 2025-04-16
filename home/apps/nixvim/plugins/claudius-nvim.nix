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
              rev = "v25.04-1";
              hash = "sha256-VZASKA8XpwT7goRqG14IxZQx8U04easn2SROjvap8K4=";
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
