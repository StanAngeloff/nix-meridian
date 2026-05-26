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
        rev = "aab70e6ba89a2e75ee799a24d2a77a2b2942c6cd";
        hash = "sha256-3zTm+VQfKAYbyzuN66+3Hks/Mt4PWVwHzpdF3PLm/3s=";
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
        path = lib.getExe pkgs.mcporter;
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
      "$kimi" = {
        provider = "moonshot";
        model = "kimi-k2.6";
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
