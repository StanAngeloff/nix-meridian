{ pkgs, pkgs-unstable, ... }:
let
  blade = pkgs.tree-sitter.buildGrammar rec {
    language = "blade";
    version = "0.11.0";
    src = pkgs.fetchFromGitHub {
      owner = "EmranMR";
      repo = "tree-sitter-blade";
      rev = "v${version}";
      hash = "sha256-PTGdsXlLoE+xlU0uWOU6LQalX4fhJ/qhpyEKmTAazLU=";
    };
    meta.homepage = "https://github.com/EmranMR/tree-sitter-blade";
  };
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

      # See https://github.com/nix-community/nixvim/blob/nixos-25.05/plugins/by-name/treesitter/default.nix#L87
      grammarPackages = pkgs.vimPlugins.nvim-treesitter.passthru.allGrammars ++ [
        blade
        terraform
      ];
    };

    extraPlugins = [
      blade
      terraform
    ];

    extraConfigLua = # lua
      ''
        local parser_configs = require("nvim-treesitter.parsers").get_parser_configs();

        parser_configs.blade = { install_info = { url = "${blade}", files = {"src/parser.c"} }, filetype = "blade" }
        parser_configs.terraform = { install_info = { url = "${terraform}", files = {"src/parser.c"} }, filetype = "tf" }
      '';
  };
}
