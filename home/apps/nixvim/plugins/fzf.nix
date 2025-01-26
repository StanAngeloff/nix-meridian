{
  programs.nixvim.plugins.fzf-lua = {
    enable = true;

    keymaps = {
      "<leader>o" = {
        action = "git_files";
        settings = {
          cmd = "git ls-files --cached --others";
        };
      };
    };
  };
}
