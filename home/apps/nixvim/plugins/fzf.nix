{
  programs.nixvim.plugins.fzf-lua = {
    enable = true;

    settings = {
      fzf_opts = {
        "--history".__raw = "vim.fn.stdpath('data') .. '/fzf-lua-history'";
      };
      winopts = {
        treesitter = true;
        split = "botright new";
        border = "none";
      };
      actions = {
        git_files = {
          "enter" = "tabedit";
          "ctrl-t" = "tab split";
        };
      };
    };

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
