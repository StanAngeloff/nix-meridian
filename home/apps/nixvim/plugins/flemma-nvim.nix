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
        rev = "fc95a9f9ec6d43527b27e5597eddfc501db8c560";
        hash = "sha256-eyQFOfI4rg1JRJbNb/IVB6tgqlBkWBySBbwBxbnQ/ug=";
      };

      postInstall = ''
        substituteInPlace $target/lua/flemma/secrets/resolvers/gcloud.lua \
          --replace "(\"gcloud\")" "(\"${pkgs.google-cloud-sdk}/bin/gcloud\")" \
          --replace "\"gcloud\"," "\"${pkgs.google-cloud-sdk}/bin/gcloud\","
      '';
    }
  );
  flemma-settings = {
    model = "$gemini-3";
    parameters = {
      thinking = "max";
      timeout = 600;
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
