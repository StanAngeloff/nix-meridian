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
              rev = "3aba6f8dad04396e94bd9df161e0839fe87d9779";
              hash = "sha256-3kuAo1yDw6DZ71I9ONIghs6Tu+q+cI161w13JmiKATs=";
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
