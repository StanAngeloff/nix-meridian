{
  programs.nixvim.plugins.treesitter-textobjects = {
    enable = true;

    settings = {
      select = {
        enable = true;

        lookahead = true;
        includeSurroundingWhitespace = false;

        keymaps = {
          "ic" = "@comment.outer";
        };
      };
    };
  };
}
