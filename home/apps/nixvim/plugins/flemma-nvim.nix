{
  config,
  lib,
  pkgs,
  ...
}:
let
  gcloud-project-id = "stans-playground";
  gcloud-default-location = "europe-central2"; # Warsaw, Poland, Europe
  flemma-nvim = (
    pkgs.vimUtils.buildVimPlugin {
      name = "flemma.nvim";
      src = pkgs.fetchFromGitHub {
        owner = "Flemma-Dev";
        repo = "flemma.nvim";
        rev = "f88449f35731acbaeb3026926855c42c5bd8f638";
        hash = "sha256-hnX1lFKnLHFdNDyzvjefJbiyaiGjR1Ls/ZZsxD8PjJE=";
      };

      postInstall = ''
        substituteInPlace $target/lua/flemma/provider/providers/vertex.lua \
          --replace gcloud "${pkgs.google-cloud-sdk}/bin/gcloud"
      '';
    }
  );
  flemma-settings = {
    model = "$gemini-3";
    parameters = {
      max_tokens = 64000;
      thinking = "max";
      timeout = 300;
      vertex = {
        location = gcloud-default-location;
        project_id = gcloud-project-id;
      };
    };
    sandbox = {
      backend = "required";
      backends = {
        bwrap = {
          path = lib.getExe pkgs.bubblewrap;
        };
      };
    };
    editing = {
      auto_write = true;
    };
    presets = {
      "$gemini-2.5" = {
        provider = "vertex";
        model = "gemini-2.5-pro";
      };
      "$gemini-3" = {
        provider = "vertex";
        model = "gemini-3-pro-preview";
        location = "global";
      };
      "$sonnet-4-5" = {
        provider = "anthropic";
        model = "claude-sonnet-4-5";
      };
      "$opus-4-6" = {
        provider = "anthropic";
        model = "claude-opus-4-6";
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
