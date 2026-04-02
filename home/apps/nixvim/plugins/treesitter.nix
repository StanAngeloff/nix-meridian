{ pkgs, pkgs-unstable, ... }:
let
  terraform = pkgs-unstable.vimPlugins.nvim-treesitter-parsers.terraform;
in
{
  programs.nixvim = {
    plugins.treesitter = {
      enable = true;

      folding = true;

      settings = {
        highlight = {
          enable = true;
        };
        indent = {
          enable = true;
        };
      };

      # See https://github.com/nix-community/nixvim/blob/nixos-25.11/plugins/by-name/treesitter/default.nix#L85
      grammarPackages = pkgs.vimPlugins.nvim-treesitter.passthru.allGrammars ++ [
        terraform
      ];
    };

    extraPlugins = [
      terraform
    ];

    extraConfigLua = # lua
      ''
        local parser_configs = require("nvim-treesitter.parsers").get_parser_configs();

        parser_configs.terraform = { install_info = { url = "${terraform}", files = {"src/parser.c"} }, filetype = "tf" }
      '';
  };
}
