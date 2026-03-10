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
        rev = "0f68b6a59ba9d096f1791584dee6eec128921d49";
        hash = "sha256-LTR+IPLv/shn4MNjalHChvEkHmBLG93T6cm5tb0GaOE=";
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
      thinking = "max";
      timeout = 300;
      vertex = {
        location = gcloud-default-location;
        project_id = gcloud-project-id;
      };
    };
    diagnostics = {
      enabled = true;
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
        model = "gemini-3.1-pro-preview";
        location = "global";
      };
      "$sonnet" = {
        provider = "anthropic";
        model = "claude-sonnet-4-6";
      };
      "$opus" = {
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

    extraConfigLua =
      with config.lib.nixvim; # lua
      ''
        require("flemma").setup(${toLuaObject flemma-settings})
      '';
  };
}
