{
  config,
  lib,
  pkgs,
  ...
}:
let
  gcloud-project-id = "angeloff-sandbox";
  gcloud-default-location = "europe-central2"; # Warsaw, Poland, Europe
  flemma-nvim = (
    pkgs.vimUtils.buildVimPlugin {
      name = "flemma.nvim";
      src = pkgs.fetchFromGitHub {
        owner = "Flemma-Dev";
        repo = "flemma.nvim";
        rev = "a64c027385c326708beb335698af0e5f382faf7e";
        hash = "sha256-Ltz1Z0S11z22BsCuwNXw5rodakfRQ3rFFtd0/PdE1nc=";
      };
    }
  );
  flemma-settings = {
    model = "$gemini";
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
    templating = {
      modules = [ "flemma-nvim.tools.stub" ];
    };
    editing = {
      auto_write = true;
    };
    presets = {
      "$gemini" = {
        provider = "vertex";
        model = "gemini-3.1-pro-preview";
        location = "global";
      };
      "$opus" = {
        provider = "anthropic";
        model = "claude-opus-5";
      };
      "$sonnet" = {
        provider = "anthropic";
        model = "claude-sonnet-5";
      };
      "$haiku" = {
        provider = "anthropic";
        model = "claude-haiku-4-5";
      };
      "$gpt" = {
        provider = "openai";
        model = "gpt-5.6";
      };
      "$kimi" = {
        provider = "moonshot";
        model = "kimi-k3";
      };
    };
  };
in
{
  programs.nixvim = {
    extraPlugins = [
      flemma-nvim
    ];

    extraFiles."lua/flemma-nvim/tools/stub.lua".source = ./tools/stub.lua;

    extraConfigLua =
      with config.lib.nixvim; # lua
      ''
        require("flemma").setup(${toLuaObject flemma-settings})
      '';
  };
}
