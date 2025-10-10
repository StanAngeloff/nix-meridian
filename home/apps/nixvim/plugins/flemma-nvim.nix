{ config, pkgs, ... }:
let
  nixvim = config.lib.nixvim;
  flemma-nvim = (
    pkgs.vimUtils.buildVimPlugin {
      name = "flemma.nvim";
      src = pkgs.fetchFromGitHub {
        owner = "Flemma-Dev";
        repo = "flemma.nvim";
        rev = "f144e4a811715a3db7ef1a68ae3323ba8b3bea21";
        hash = "sha256-GnrCFJ0x5h2e1nuJch4moCOJ3PPExhVhKXOTiHc1GM8=";
      };

      postInstall = ''
        substituteInPlace $target/lua/flemma/provider/providers/vertex.lua \
          --replace gcloud "${pkgs.google-cloud-sdk}/bin/gcloud"
      '';
    }
  );
  flemma-settings = {
    provider = "vertex";
    # model = "…"; # The latest Gemini Pro model will be used by default.
    parameters = {
      max_tokens = 65536;
      timeout = 300;
      project_id = "stans-playground";
      vertex = {
        location = "europe-central2"; # Warsaw, Poland, Europe
        thinking_budget = 32768;
      };
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
      user_lua_expression = "#ff00ff";
      user_file_reference = "#ff00ff";
    };
  };
in
{
  programs.nixvim = {
    extraPlugins = [ flemma-nvim ];

    extraConfigLua = ''
      require("flemma").setup(${nixvim.toLuaObject flemma-settings});
    '';
  };
}
