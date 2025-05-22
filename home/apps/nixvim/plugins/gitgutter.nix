{
  programs.nixvim.plugins.gitgutter = {
    enable = true;

    settings = {
      map_keys = false;
      max_signs = 9999;

      sign_added = "│";
      sign_modified = "│";
      sign_removed = "_";
      sign_removed_first_line = "‾";
      sign_removed_above_and_below = "-";
      sign_modified_removed = "-";
    };
  };
}
