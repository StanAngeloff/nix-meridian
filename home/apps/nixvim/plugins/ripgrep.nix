{
  programs.nixvim.opts = {
    grepprg = "rg --vimgrep --no-heading";
    grepformat = "%f:%l:%c:%m,%f:%l:%m";
  };
}
