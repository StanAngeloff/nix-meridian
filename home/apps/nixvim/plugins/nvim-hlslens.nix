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
        calm_down = false,
        nearest_only = true,
        override_lens = function(render, posList, nearest, idx, relIdx)
          if vim.startswith(vim.bo.filetype, 'fff_') then
            return
          end
          local sfw = vim.v.searchforward == 1
          local indicator, text, chunks
          local absRelIdx = math.abs(relIdx)
          if absRelIdx > 1 then
            -- indicator = ('%d%s'):format(absRelIdx, sfw ~= (relIdx > 1) and 'N' or 'n')
            return
          elseif absRelIdx == 1 then
            -- indicator = sfw ~= (relIdx == 1) and 'N' or 'n'
            return
          else
            indicator = ""
          end
          local lnum, col = unpack(posList[idx])
          if nearest then
            local cnt = #posList
            if indicator ~= "" then
              text = ('❬%s %d/%d❭'):format(indicator, idx, cnt)
            else
              text = ('❬%d/%d❭'):format(idx, cnt)
            end
            chunks = {{' '}, {text, 'HlSearchLensNear'}}
          else
            text = ('❬%s %d❭'):format(indicator, idx)
            chunks = {{' '}, {text, 'HlSearchLens'}}
          end
          render.setVirt(0, lnum - 1, col - 1, chunks, nearest)
        end
      })

      -- Mappings
      --
      local kopts = { noremap = true, silent = true }

      vim.api.nvim_set_keymap('n', 'n', [[<Cmd>execute('normal! ' . v:count1 . 'n')<CR><Cmd>lua require('hlslens').start()<CR>]], kopts)
      vim.api.nvim_set_keymap('n', 'N', [[<Cmd>execute('normal! ' . v:count1 . 'N')<CR><Cmd>lua require('hlslens').start()<CR>]], kopts)
      vim.api.nvim_set_keymap('n', '*', [[<Cmd>keepjumps normal! mi*`i<CR><Cmd>lua require('hlslens').start()<CR>]], kopts)
      vim.api.nvim_set_keymap('n', '#', [[<Cmd>keepjumps normal! mi#`i<CR><Cmd>lua require('hlslens').start()<CR>]], kopts)
      vim.api.nvim_set_keymap('n', 'g*', [[g*<Cmd>lua require('hlslens').start()<CR>]], kopts)
      vim.api.nvim_set_keymap('n', 'g#', [[g#<Cmd>lua require('hlslens').start()<CR>]], kopts)

      vim.api.nvim_set_keymap('n', '<Leader>l', '<Cmd>noh<CR>', kopts)

      -- Highlighting
      --
      vim.api.nvim_set_hl(0, "HlSearchLensNear", { fg = "#aaaa00" })
    '';
  };
}
