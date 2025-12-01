{
  programs.nixvim.plugins.lspsaga = {
    enable = true;

    settings = {
      definition = {
        keys = {
          edit = "<CR>";
          vsplit = "v";
          split = "i";
          tabe = "t";
          quit = "q";
        };
      };
      symbol_in_winbar = {
        enable = false;
      };
      implement = {
        enable = false;
      };
      lightbulb = {
        enable = false;
      };
    };
  };
}
