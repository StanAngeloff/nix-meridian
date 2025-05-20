{ config, pkgs, ... }:
let
  nixvim = config.lib.nixvim;
  claudius-nvim = (
    pkgs.vimUtils.buildVimPlugin {
      name = "claudius.nvim";
      src = pkgs.fetchFromGitHub {
        owner = "StanAngeloff";
        repo = "claudius.nvim";
        rev = "3aba6f8dad04396e94bd9df161e0839fe87d9779";
        hash = "sha256-3kuAo1yDw6DZ71I9ONIghs6Tu+q+cI161w13JmiKATs=";
      };

      postInstall = ''
        substituteInPlace $target/lua/claudius/provider/vertex.lua \
          --replace gcloud "${pkgs.google-cloud-sdk}/bin/gcloud"
      '';
    }
  );
  claudius-settings = {
    provider = "vertex";
    model = "gemini-2.5-pro-preview-05-06";
    parameters = {
      max_tokens = 8000;
      timeout = 300;
      project_id = "stans-playground";
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
    extraPlugins = [ claudius-nvim ];

    extraConfigLua = ''
      require("claudius").setup(${nixvim.toLuaObject claudius-settings});
    '';
  };
}
