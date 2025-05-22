{ pkgs, ... }:
# See https://github.com/nix-community/nixvim/blob/nixos-25.05/plugins/by-name/treesitter/default.nix#L87
let
  tree-sitter-blade = pkgs.tree-sitter.buildGrammar rec {
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

      grammarPackages = pkgs.vimPlugins.nvim-treesitter.passthru.allGrammars ++ [
        tree-sitter-blade
      ];
    };

    extraPlugins = [
      tree-sitter-blade
    ];

    extraConfigLua = # lua
      ''
        require("nvim-treesitter.parsers").get_parser_configs().blade = {
          install_info = {
            url = "https://github.com/EmranMR/tree-sitter-blade",
            files = {"src/parser.c"},
            branch = "main",
          },
          filetype = "blade",
        }
      '';
  };
}
