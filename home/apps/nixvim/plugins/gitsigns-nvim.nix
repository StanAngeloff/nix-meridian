{
  programs.nixvim.plugins.gitsigns = {
    enable = true;

    settings = {
      signs = {
        add.text = "│";
        change.text = "│";
        delete.text = "_";
        topdelete.text = "‾";
        changedelete.text = "-";
        untracked.text = "┆";
      };
      signs_staged = {
        add.text = "│";
        change.text = "│";
        delete.text = "_";
        topdelete.text = "‾";
        changedelete.text = "-";
      };
      signs_staged_enable = true;
    };

    luaConfig.post = # lua
      ''
        vim.api.nvim_set_hl(0, "GitSignsAdd", { fg = "#74ff74", bg="#1d401d" })
        vim.api.nvim_set_hl(0, "GitSignsChange", { fg = "#ccaa00", bg="#333000" })
        vim.api.nvim_set_hl(0, "GitSignsChangedelete", { fg = "#ccaa00", bg="#333000" })
        vim.api.nvim_set_hl(0, "GitSignsDelete", { fg = "#ff7474", bg="#401d1d" })
        vim.api.nvim_set_hl(0, "GitSignsTopdelete", { fg = "#ff7474", bg="#401d1d" })
        vim.api.nvim_set_hl(0, "GitSignsUntracked", { fg = "#747474", bg="#333333" })

        -- As above with 50% lightness in HSL color space.
        vim.api.nvim_set_hl(0, "GitSignsStagedAdd", { fg = "#00ba00" })
        vim.api.nvim_set_hl(0, "GitSignsStagedChange", { fg = "#665500" })
        vim.api.nvim_set_hl(0, "GitSignsStagedChangedelete", { fg = "#665500" })
        vim.api.nvim_set_hl(0, "GitSignsStagedDelete", { fg = "#ba0000" })
        vim.api.nvim_set_hl(0, "GitSignsStagedTopdelete", { fg = "#ba0000" })
        vim.api.nvim_set_hl(0, "GitSignsStagedUntracked", { fg = "#3a3a3a" })
      '';
  };
}
