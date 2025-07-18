{ config, pkgs, ... }:
let
  nixvim = config.lib.nixvim;
  claudius-nvim = (
    pkgs.vimUtils.buildVimPlugin {
      name = "claudius.nvim";
      src = pkgs.fetchFromGitHub {
        owner = "StanAngeloff";
        repo = "claudius.nvim";
        rev = "88b825f206ec2a759b9e8b8cc0b88cb12a064ea7";
        hash = "sha256-2zZ1CXHY6qLk/Hf2460r5hLwo4kL9e2xZRzNGLpHpms=";
      };

      postInstall = ''
        substituteInPlace $target/lua/claudius/provider/vertex.lua \
          --replace gcloud "${pkgs.google-cloud-sdk}/bin/gcloud"
      '';
    }
  );
  claudius-settings = {
    provider = "vertex";
    # model = "…"; # The latest Gemini Pro model will be used by default.
    parameters = {
      max_tokens = 65536;
      timeout = 300;
      project_id = "stans-playground";
      vertex = {
        thinking_budget = 32768;
      };
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
      user_lua_expression = "#ff00ff";
      user_file_reference = "#ff00ff";
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
