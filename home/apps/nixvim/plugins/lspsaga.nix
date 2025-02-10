{
  programs.nixvim.plugins.lspsaga = {
    enable = true;

    definition = {
      keys = {
        edit = "<CR>";
        vsplit = "v";
        split = "i";
        tabe = "t";
        quit = "q";
      };
    };
    symbolInWinbar = {
      enable = false;
    };
    lightbulb = {
      enable = false;
    };
  };
}
