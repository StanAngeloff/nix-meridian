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
        rev = "57fe12d9eade02889064f2b261e2c70e8c654cbe";
        hash = "sha256-5s/wcnXG6p4RBZaXz5U85PJsUkAnR+A7pc72jtp1kJs=";
      };

      postInstall = ''
        substituteInPlace $target/lua/flemma/provider/providers/vertex.lua \
          --replace gcloud "${pkgs.google-cloud-sdk}/bin/gcloud"
      '';
    }
  );
  flemma-settings = {
    presets = {
      "$gemini-2.5" = {
        provider = "vertex";
        model = "gemini-2.5-pro";
        project_id = gcloud-project-id;
        location = gcloud-location;
        max_tokens = 65536;
        thinking_budget = 32768;
      };
      "$gemini-3" = {
        provider = "vertex";
        model = "gemini-3-pro-preview";
        project_id = gcloud-project-id;
        location = "global";
        max_tokens = 65536;
        thinking_budget = 32768;
      };
      "$opus-4-5" = {
        provider = "anthropic";
        model = "claude-opus-4-5";
        max_tokens = 64000;
        reasoning = "high";
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
