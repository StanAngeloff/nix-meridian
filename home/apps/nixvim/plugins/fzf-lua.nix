{
  programs.nixvim.plugins.fzf-lua = {
    enable = true;

    luaConfig.pre = # lua
      ''
        -- Register fzf-lua as the UI interface for `vim.ui.select`
        require('fzf-lua').register_ui_select()

        vim.api.nvim_set_hl(0, "FzfLuaPreviewBorder", { fg = "#262626" })
        vim.api.nvim_set_hl(0, "FzfLuaLivePrompt", { link = "Normal" })
      '';

    settings = {
      fzf_opts = {
        "--history".__raw = "vim.fn.stdpath('data') .. '/fzf-lua-history'";
      };
      grep = {
        rg_opts = builtins.concatStringsSep " " [
          "--column --line-number --no-heading --max-columns=4096 --color=always"
          # NOTE: See home/apps/ripgrep/default.nix - the default ripgrep configuration is not read by fzf.
          "--hidden"
          "--ignore-vcs"
          "--smart-case"
          "--auto-hybrid-regex"
          "--glob=\"!.git/*\""
          "--glob=\"!node_modules/*\""
          "--colors=line:fg:yellow"
          "--colors=line:style:bold"
          "--colors=path:fg:green"
          "--colors=path:style:bold"
          "--colors=match:fg:black"
          "--colors=match:bg:yellow"
          "--colors=match:style:nobold"
          "-e"
        ];
      };
      winopts = {
        treesitter = true;
        split = "botright new";
        border = "none";
        preview = {
          border = "single";
          winopts = {
            border = "none";
          };
        };
      };
      keymap = {
        fzf = {
          "ctrl-a" = "select-all";
        };
      };
      actions = {
        files = {
          "enter".__raw = "require('fzf-lua.actions').file_edit_or_qf";
          "ctrl-t".__raw = "require('fzf-lua.actions').file_tabedit";
        };
      };
    };

    keymaps = {
      "<leader>o" = {
        action = "git_files";
        settings = {
          cmd = "git ls-files --cached --others --exclude-standard";
        };
      };
    };
  };
}
