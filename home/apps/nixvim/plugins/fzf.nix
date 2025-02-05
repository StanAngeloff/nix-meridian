{
  programs.nixvim.plugins.fzf-lua = {
    enable = true;

    luaConfig.pre = ''
      local fzf_lua_actions = require'fzf-lua.actions'
    '';

    settings = {
      fzf_opts = {
        "--history".__raw = "vim.fn.stdpath('data') .. '/fzf-lua-history'";
      };
      winopts = {
        treesitter = true;
        split = "botright new";
        border = "none";
      };
      keymap = {
        fzf = {
          "ctrl-a" = "select-all";
        };
      };
      actions = {
        files = {
          "enter".__raw = "fzf_lua_actions.file_edit_or_qf";
          "ctrl-t".__raw = "fzf_lua_actions.file_tabedit";
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
