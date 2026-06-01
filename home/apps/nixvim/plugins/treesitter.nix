{ config, pkgs-unstable, ... }:
let
  terraform = pkgs-unstable.vimPlugins.nvim-treesitter-parsers.terraform;
in
{
  programs.nixvim = {
    plugins.treesitter = {
      enable = true;

      folding.enable = true;

      highlight.enable = true;
      indent.enable = true;

      # See https://github.com/nix-community/nixvim/blob/nixos-26.05/plugins/by-name/treesitter/default.nix#L51
      grammarPackages = config.programs.nixvim.plugins.treesitter.package.allGrammars ++ [
        terraform
      ];

      languageRegister.terraform = "tf";
    };

    extraPlugins = [
      terraform
    ];
  };
}
