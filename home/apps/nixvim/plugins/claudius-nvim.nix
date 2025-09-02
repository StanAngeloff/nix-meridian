{ config, pkgs, ... }:
let
  nixvim = config.lib.nixvim;
  claudius-nvim = (
    pkgs.vimUtils.buildVimPlugin {
      name = "claudius.nvim";
      src = pkgs.fetchFromGitHub {
        owner = "StanAngeloff";
        repo = "claudius.nvim";
        rev = "9ae6792392540958e713264e6eefcf4ae8bd3db6";
        hash = "sha256-DajJbK3HIuvjhwVov5KqUButqXokgh7y9jiJl4/CY/A=";
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
        location = "europe-central2"; # Warsaw, Poland, Europe
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
