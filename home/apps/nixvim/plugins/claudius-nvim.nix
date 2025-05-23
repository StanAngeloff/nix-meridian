{ config, pkgs, ... }:
let
  nixvim = config.lib.nixvim;
  claudius-nvim = (
    pkgs.vimUtils.buildVimPlugin {
      name = "claudius.nvim";
      src = pkgs.fetchFromGitHub {
        owner = "StanAngeloff";
        repo = "claudius.nvim";
        rev = "2f404a1702bcd8997fa2cb4f80225fd1ddda2f70";
        hash = "sha256-1wv0QITDDfd12UA2HyfXiGqbSKq8mHxwQvUZGX7fh50=";
      };

      postInstall = ''
        substituteInPlace $target/lua/claudius/provider/vertex.lua \
          --replace gcloud "${pkgs.google-cloud-sdk}/bin/gcloud"
      '';
    }
  );
  claudius-settings = {
    provider = "vertex";
    model = "gemini-2.5-pro-preview-05-06";
    parameters = {
      max_tokens = 8000;
      timeout = 300;
      project_id = "stans-playground";
    };
    editing = {
      auto_write = true;
    };
    pricing = {
      enabled = true;
    };
    ruler = {
      char = "━";
    };
    signs = {
      enabled = true;
      assistant = {
        hl = "#8f9fdf";
      };
      user = {
        char = "▏";
        hl = "#6f6f6f";
      };
    };
    highlights = {
      assistant = "#8f9faf";
    };
  };
in
{
  programs.nixvim = {
    extraPlugins = [ claudius-nvim ];

    extraConfigLua = ''
      require("claudius").setup(${nixvim.toLuaObject claudius-settings});
    '';
  };
}
