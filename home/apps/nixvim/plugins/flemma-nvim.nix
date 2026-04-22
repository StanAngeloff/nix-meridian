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
        rev = "ee446b47d5a6b547403bedb9d4d1c468a9db4a77";
        hash = "sha256-DnAkyBLh4HKcgR8nOIu91t/pYdlrt2+xP0HlOHO0z9s=";
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
    tools = {
      mcporter = {
        enabled = true;
      };
    };
    diagnostics = {
      enabled = true;
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
      format = "#{?#{booting},⏳,}#{model}#{?#{thinking}, (#{thinking}),}#{?#{session.cost}, | Σ#{session.requests} #{session.cost},}#{?#{buffer.tokens.input}, | #{buffer.tokens.input}↑,}";
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
