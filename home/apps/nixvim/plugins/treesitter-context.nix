{
  programs.nixvim.plugins.treesitter-context = {
    enable = true;

    settings = {
      enable = true;
      max_lines = 10;
      min_window_height = 0;
      line_numbers = false;
      multiline_threshold = 20;
      trim_scope = "outer";
      mode = "cursor";
      separator = null;
      zindex = 20;
      on_attach = null;
    };
  };
}
