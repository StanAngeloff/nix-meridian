{
  config,
  lib,
  pkgs,
  ...
}:
let
  gcloud-project-id = "stans-playground";
  gcloud-location = "europe-central2"; # Warsaw, Poland, Europe
  flemma-nvim = (
    pkgs.vimUtils.buildVimPlugin {
      name = "flemma.nvim";
      src = pkgs.fetchFromGitHub {
        owner = "Flemma-Dev";
        repo = "flemma.nvim";
        rev = "v0.2.0";
        hash = "sha256-4sY4TSorNQJhWPpD2ek6esfGhYfwXpZr+E5Q3YGF8eE=";
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
        location = gcloud-location;
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
    provider = "vertex";
    parameters = {
      max_tokens = 64000;
      thinking = "max";
      timeout = 300;
      vertex = {
        location = gcloud-location;
        project_id = gcloud-project-id;
        thinking_budget = 32768;
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
