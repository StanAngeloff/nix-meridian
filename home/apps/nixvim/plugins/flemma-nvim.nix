{ config, pkgs, ... }:
let
  gcloud-project-id = "stans-playground";
  gcloud-location = "europe-central2"; # Warsaw, Poland, Europe
  flemma-nvim = (
    pkgs.vimUtils.buildVimPlugin {
      name = "flemma.nvim";
      src = pkgs.fetchFromGitHub {
        owner = "Flemma-Dev";
        repo = "flemma.nvim";
        rev = "b30367fd5169095f7032c19dbbc0c8d6c45294ff";
        hash = "sha256-MZl3AGi6BTXFUerIaVCVvILkg3PAWtEVcwlIrHKJuC8=";
      };

      postInstall = ''
        substituteInPlace $target/lua/flemma/provider/providers/vertex.lua \
          --replace gcloud "${pkgs.google-cloud-sdk}/bin/gcloud"
      '';
    }
  );
  flemma-settings = {
    presets = {
      "$gemini" = {
        provider = "vertex";
        model = "gemini-2.5-pro";
        project_id = gcloud-project-id;
        location = gcloud-location;
        max_tokens = 65536;
        thinking_budget = 32768;
      };
    };
    provider = "vertex";
    # model = "…"; # The latest Gemini Pro model will be used by default.
    parameters = {
      max_tokens = 65536;
      timeout = 300;
      project_id = gcloud-project-id;
      vertex = {
        location = gcloud-location;
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
      thinking_tag = {
        fg = "#6f7f8f";
        bold = true;
        underline = true;
      };
      thinking_block = {
        fg = "#6f7f8f";
      };
    };
  };
in
{
  programs.nixvim = {
    extraPlugins = [
      flemma-nvim
    ];

    extraConfigLua = with config.lib.nixvim; ''
      require("flemma").setup(${toLuaObject flemma-settings});
    '';
  };
}
