{ pkgs, ... }:
{
  programs.nixvim = {
    extraPlugins = with pkgs.vimPlugins; [
      nerdtree
      vim-nerdtree-tabs
      nerdtree-git-plugin
    ];

    extraConfigLua = ''
      function _G.NERDTreeReveal()
        vim.cmd("wincmd p")
        vim.cmd("silent! NERDTreeFind")
      end

      function _G.NERDTreeTrashNode()
        local selected = vim.fn.eval('g:NERDTreeFileNode.GetSelected().path.str()')
        vim.fn.timer_start(1, function()
          vim.api.nvim_feedkeys(":Trash " .. vim.fn.fnameescape(selected), "n", true)
        end)
      end

      function _G.NERDTreeSearchInCurrentNode()
        local selected = vim.fn.eval('g:NERDTreeFileNode.GetSelected().path.str()')
        if vim.fn.isdirectory(selected) then
          vim.fn.timer_start(1, function()
            require("fzf-lua").live_grep({ cwd = selected })
          end)
        end
      end
    '';

    extraConfigVim = ''
      function! NERDTreeRevealBridge()
        lua NERDTreeReveal()
      endfunction

      function NERDTreeTrashNodeBridge()
        lua NERDTreeTrashNode()
      endfunction

      function NERDTreeSearchInCurrentNodeBridge()
        lua NERDTreeSearchInCurrentNode()
      endfunction
    '';

    globals = {
      TreeDirArrows = 1;
      NERDTreeChDirMode = 1;
      NERDTreeMinimalUI = 1;
      NERDTreeWinSize = 48;
      NERDTreeIgnore = ["\~$" "\.pyc$" "^node_modules$"];
      NERDTreeMapJumpNextSibling = "";
      NERDTreeMapJumpPrevSibling = "";
      NERDTreeShowHidden = 1;
      NERDTreeQuitOnOpen = 1;
      # Free up "?" for reverse search.
      NERDTreeMapHelp = "H";
      # Don't ask if buffers should be deleted on rename.
      NERDTreeAutoDeleteBuffer = 1;
      NERDTreeNaturalSort = 1;
      NERDTreeDirArrowExpandable = "▶";
      NERDTreeDirArrowCollapsible = "▼";
      # Be safe!
      NERDTreeRemoveDirCmd = "trash ";

      nerdtree_tabs_open_on_new_tab = 0;
      nerdtree_tabs_focus_on_files = 1;

      NERDTreeGitStatusShowClean = 1;
      NERDTreeGitStatusConcealBrackets = 1;

      NERDTreeGitStatusIndicatorMapCustom = {
        "Untracked" ="⁇";
        "Staged"    ="⊕";
        "Dirty"     ="•";
        "Modified"  ="•";
        "Unmerged"  ="⊜";
        "Renamed"   ="⎊";
        "Deleted"   ="⊗";
        "Clean"     ="·";
        "Ignored"   ="☒";
        "Unknown"   ="U";
      };
    };

    autoCmd = [
      {
        # Make sure a NERDTree instance is mirrored for all tabs.
        # This is needed as if the buffer with the only NERDTree instance is closed,
        # the state is reset for the next mirror.
        event = [ "TabEnter" ];
        pattern = "*";
        callback.__raw = ''
          function()
            if vim.t.hasNERDTree == nil then
              vim.cmd("silent! NERDTreeMirrorOpen")
              vim.cmd("silent! NERDTreeMirrorToggle")
              vim.t.hasNERDTree = 1
            end
          end
        '';
      }
      {
        event = [ "VimEnter" ];
        pattern = "*";
        callback.__raw = ''
          function()
            vim.fn.NERDTreeAddKeyMap({ key="a", callback="NERDTreeRevealBridge", quickhelpText="reveal the node for the open file" })
            vim.fn.NERDTreeAddMenuItem({ shortcut="t", callback="NERDTreeTrashNodeBridge", text="(t)rash the current node" })
            vim.fn.NERDTreeAddKeyMap({ key="S", callback="NERDTreeSearchInCurrentNodeBridge", quickhelpText="search for a string (recursively) in the current node" })
          end
        '';
      }
    ];
  };
}
