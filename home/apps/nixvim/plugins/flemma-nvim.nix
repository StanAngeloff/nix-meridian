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
        rev = "v0.3.0";
        hash = "sha256-+xwc+zX06k45rdRPESb5SKzv4zmzzjewmLyzX1o+IPg=";
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

    extraConfigLua = with config.lib.nixvim; ''
      require("flemma").setup(${toLuaObject flemma-settings});
    '';
  };
}
