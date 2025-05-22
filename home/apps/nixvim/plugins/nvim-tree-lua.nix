{ pkgs-unstable, ... }:
{
  programs.nixvim = {
    plugins.nvim-tree = {
      enable = true;
      package = pkgs-unstable.vimPlugins.nvim-tree-lua;

      disableNetrw = true;
      reloadOnBufenter = true;

      actions = {
        openFile = {
          quitOnOpen = true;
        };
        filePopup = {
          openWinConfig = {
            border = "rounded";
          };
        };
      };

      git = {
        enable = true;
      };

      tab = {
        sync = {
          open = true;
          close = true;
        };
      };

      view = {
        width = 48;
      };

      # NOTE: `renderer.icons.glyphs.bookmark` is not available in Nixvim so we resort to using `extraOptions` which is shallow merged with the rest.
      extraOptions = {
        renderer = {
          add_trailing = true;
          highlight_git = "icon";
          icons = {
            git_placement = "signcolumn";
            glyphs = {
              bookmark = "│";
              git = {
                deleted = "D";
                ignored = "I";
                renamed = "R";
                staged = "S";
                unmerged = "C";
                unstaged = "U";
                untracked = "?";
              };
            };
          };
        };
      };

      onAttach.__raw = ''
        function(bufnr)
          local api = require("nvim-tree.api")

          local function opts(desc)
            return { desc = "nvim-tree: " .. desc, buffer = bufnr, noremap = true, silent = true, nowait = true }
          end

          -- See https://github.com/nvim-tree/nvim-tree.lua/blob/master@%7B2025-05-09%7D/lua/nvim-tree/keymap.lua
          vim.keymap.set("n", "<C-t>", api.node.open.tab, opts("Open: New Tab"))
          vim.keymap.set("n", "t", api.node.open.tab, opts("Open: New Tab"))
          vim.keymap.set("n", "<CR>", api.node.open.edit, opts("Open"))
          vim.keymap.set("n", "o", api.node.open.edit, opts("Open"))
          vim.keymap.set("n", "K", api.node.show_info_popup, opts("Info"))

          vim.keymap.set("n", ">", api.node.navigate.sibling.next, opts("Next Sibling"))
          vim.keymap.set("n", "<", api.node.navigate.sibling.prev, opts("Previous Sibling"))
          vim.keymap.set("n", "x", api.node.navigate.parent_close, opts("Close Directory"))

          vim.keymap.set("n", "ma", api.fs.create, opts("Create File Or Directory"))
          vim.keymap.set("n", "mr", api.fs.rename_full, opts("Rename"))
          vim.keymap.set("n", "md", api.fs.trash, opts("Trash"))
          vim.keymap.set("n", "y", api.fs.copy.filename, opts("Copy Name"))
          vim.keymap.set("n", "Y", api.fs.copy.relative_path, opts("Copy Relative Path"))

          vim.keymap.set("n", "q", api.tree.close, opts("Close"))
          vim.keymap.set("n", "<Tab>", api.tree.toggle, opts("Toggle"))
          vim.keymap.set("n", "R", api.tree.reload, opts("Refresh"))

          vim.keymap.set("n", "g?", api.tree.toggle_help, opts("Help"))
          vim.keymap.set("n", "C", api.tree.change_root_to_node, opts("CD"))
          vim.keymap.set("n", "U", api.tree.change_root_to_parent, opts("Up"))
          vim.keymap.set("n", "H", api.tree.toggle_hidden_filter, opts("Toggle Filter: Dotfiles"))
          vim.keymap.set("n", "I", api.tree.toggle_gitignore_filter, opts("Toggle Filter: Git Ignore"))

          vim.keymap.set("n", "<2-LeftMouse>", api.node.open.edit, opts("Open"))
          vim.keymap.set("n", "<2-RightMouse>", api.tree.change_root_to_node, opts("CD"))

          vim.keymap.set("n", "S", function ()
            local selected = api.tree.get_node_under_cursor()
            if selected and selected.type == "directory" then
              require("fzf-lua").live_grep({ cwd = selected.absolute_path })
            end
          end, opts("Search"))

          vim.keymap.set("n", "a", function ()
            api.tree.close()
            api.tree.open({ focus = true, find_file = true })
          end, opts("Find and focus the current buffer in the tree"))

          -- See https://github.com/nvim-tree/nvim-tree.lua/blob/master@%7B2025-05-09%7D/doc/nvim-tree-lua.txt#L2667
          vim.api.nvim_set_hl(0, "NvimTreeGitNewIcon", { fg = "#747474" })
          vim.api.nvim_set_hl(0, "NvimTreeGitRenamedIcon", { fg = "#00ba00" })
          vim.api.nvim_set_hl(0, "NvimTreeGitStagedIcon", { fg = "#00ba00" })
          vim.api.nvim_set_hl(0, "NvimTreeGitDirtyIcon", { fg = "#ccaa00" })
          vim.api.nvim_set_hl(0, "NvimTreeGitMergeIcon", { fg = "#61afef" })
          vim.api.nvim_set_hl(0, "NvimTreeGitDeletedIcon", { fg = "#ba0000" })
          vim.api.nvim_set_hl(0, "NvimTreeGitIgnoredIcon", { fg = "#3a3a3a" })
        end
      '';
    };
  };
}
