{ pkgs, ... }:
let
  nvim-hlslens = (
    pkgs.vimUtils.buildVimPlugin {
      name = "nvim-hlslens";
      src = pkgs.fetchFromGitHub {
        owner = "kevinhwang91";
        repo = "nvim-hlslens";
        rev = "be2d7b2be01860b5445a007ff2bc72b29896db6b";
        hash = "sha256-W+R/GY6a6easPnpndGAb8TuE+jqaYZlqT9ZQUdQnUwQ=";
      };
    }
  );
in
{
  programs.nixvim = {
    extraPlugins = [
      nvim-hlslens
    ];

    extraConfigLua = ''
      require('hlslens').setup({
        enable_incsearch = false,
        calm_down = true,
        nearest_only = true
      })

      -- Mappings
      --
      local kopts = { noremap = true, silent = true }

      vim.api.nvim_set_keymap('n', 'n', [[<Cmd>execute('normal! ' . v:count1 . 'n')<CR><Cmd>lua require('hlslens').start()<CR>]], kopts)
      vim.api.nvim_set_keymap('n', 'N', [[<Cmd>execute('normal! ' . v:count1 . 'N')<CR><Cmd>lua require('hlslens').start()<CR>]], kopts)
      vim.api.nvim_set_keymap('n', '*', [[*<Cmd>lua require('hlslens').start()<CR>]], kopts)
      vim.api.nvim_set_keymap('n', '#', [[#<Cmd>lua require('hlslens').start()<CR>]], kopts)
      vim.api.nvim_set_keymap('n', 'g*', [[g*<Cmd>lua require('hlslens').start()<CR>]], kopts)
      vim.api.nvim_set_keymap('n', 'g#', [[g#<Cmd>lua require('hlslens').start()<CR>]], kopts)

      vim.api.nvim_set_keymap('n', '<Leader>l', '<Cmd>noh<CR>', kopts)

      -- Highlighting
      --
      vim.api.nvim_set_hl(0, "HlSearchLensNear", { fg = "#aaaa00" })
    '';
  };
}
