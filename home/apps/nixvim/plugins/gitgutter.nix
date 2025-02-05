{
  programs.nixvim.plugins.gitgutter = {
    enable = true;

    maxSigns = 9999;
    defaultMaps = false;

    signs = {
      added = "│";
      modified = "│";
      removed = "_";
      removedFirstLine = "‾";
      removedAboveAndBelow = "-";
      modifiedRemoved = "-";
    };
  };
}
