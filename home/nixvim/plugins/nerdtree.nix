{ pkgs, ... }:
{
  programs.nixvim = {
    extraPlugins = with pkgs.vimPlugins; [
      nerdtree
      vim-nerdtree-tabs
    ];

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
      NERDTreeMapHelp  =  "H";
      # Don't ask if buffers should be deleted on rename.
      NERDTreeAutoDeleteBuffer = 1;
      NERDTreeNaturalSort = 1;
      NERDTreeDirArrowExpandable = "▶";
      NERDTreeDirArrowCollapsible = "▼";
      # Be safe!
      NERDTreeRemoveDirCmd = "trash ";

      nerdtree_tabs_open_on_new_tab = 0;
      nerdtree_tabs_focus_on_files = 1;
    };

    autoCmd = [
      {
        # Make sure a NERDTree instance is mirrored for all tabs.
        # This is needed as if the buffer with the only NERDTree instance is closed,
        # the state is reset for the next mirror.
        event = "TabEnter";
        pattern = "*";
        command = ''
          if !exists('t:hasNERDTree')
            let t:hasNERDTree=1
            execute 'silent! NERDTreeMirrorOpen'
            execute 'silent! NERDTreeMirrorToggle'
          endif
        '';
      }
    ];
  };
}
