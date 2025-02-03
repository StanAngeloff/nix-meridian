{
  programs.nixvim.plugins.treesitter-textobjects = {
    enable = true;

    select = {
      enable = true;

      lookahead = true;
      includeSurroundingWhitespace = false;

      keymaps = {
        "ic" = "@comment.outer";
      };
    };
  };
}
