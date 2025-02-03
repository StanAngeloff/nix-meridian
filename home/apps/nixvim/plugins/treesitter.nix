{
  programs.nixvim.plugins.treesitter = {
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

    # NOTE: By default, **all** available grammars packaged in the `nvim-treesitter` package are installed.
    #grammarPackages = with pkgs.vimPlugins.nvim-treesitter.builtGrammars; [
    #  nix
    #];
  };
}
