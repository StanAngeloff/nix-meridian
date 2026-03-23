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
        rev = "2b7160225e97c3fd7a4dea6a880a5fcb5b8dccf6";
        hash = "sha256-eJSsctD1uHk9CNTPu6d2YXL50rTi2qm7DMfvraq8Lp0=";
      };
    }
  );
  flemma-settings = {
    model = "$gemini-3";
    parameters = {
      thinking = "max";
      vertex = {
        location = gcloud-default-location;
        project_id = gcloud-project-id;
      };
    };
    diagnostics = {
      enabled = true;
    };
    experimental = {
      lsp = true;
      tools = true;
    };
    secrets = {
      gcloud = {
        path = "${pkgs.google-cloud-sdk}/bin/gcloud";
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
    statusline = {
      format = "#{model}#{?#{thinking}, (#{thinking}),}#{?#{booting}, ⏳,}#{?#{session.cost},  │  Σ#{session.requests}  #{session.cost},}";
    };
    presets = {
      "$gemini-3" = {
        provider = "vertex";
        model = "gemini-3.1-pro-preview";
        location = "global";
      };
      "$gemini-2.5" = {
        provider = "vertex";
        model = "gemini-2.5-pro";
      };
      "$opus" = {
        provider = "anthropic";
        model = "claude-opus-4-6";
      };
      "$sonnet" = {
        provider = "anthropic";
        model = "claude-sonnet-4-6";
      };
      "$gpt" = {
        provider = "openai";
        model = "gpt-5.4";
      };
    };
  };
in
{
  programs.nixvim = {
    extraPlugins = [
      flemma-nvim
    ];

    extraConfigLua =
      with config.lib.nixvim; # lua
      ''
        require("flemma").setup(${toLuaObject flemma-settings})
      '';
  };
}
