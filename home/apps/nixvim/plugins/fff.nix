{ pkgs-unstable, ... }:
{
  # fff-nvim's Rust core and grep only exist on recent releases; pin to unstable (0.9.x)
  # rather than the stable channel's 0.8.4, which lacks live grep entirely.
  programs.nixvim.plugins.fff = {
    enable = true;
    package = pkgs-unstable.vimPlugins.fff-nvim;

    settings = {
      layout = {
        # Dock the picker to the bottom of the screen as a full-width, half-height panel,
        # approximating the old fzf-lua `botright new` split.
        anchor = "bottom";
        width = 1.0;
        height = 0.5;
        # Search box on top, results below. Matches the old fzf reverse layout and, as a
        # side effect, makes <Tab> multi-select walk down the list rather than up (fff ties
        # the select-and-advance direction to the prompt position).
        prompt_position = "top";
        show_scrollbar = true;
      };

      # Open content grep in fuzzy mode; <S-Tab> cycles fuzzy -> plain -> regex.
      grep.modes = [
        "regex"
        "plain"
        "fuzzy"
      ];

      # Rank purely by match quality so exact/prefix hits win. fff otherwise buries a fresh
      # exact match under frecency and the 100x query-combo boost. history stays enabled (only
      # its score boost is neutralised) so <C-p>/<C-n> can still cycle previous queries.
      frecency.enabled = false;
      history.combo_boost_score_multiplier = 1;

      keymaps = {
        # Arrows and C-k/C-j move the list. fff binds C-p/C-n to navigation by default, but
        # we free them for query-history cycling below to match fzf's `--history` behaviour.
        move_up = [
          "<Up>"
          "<C-k>"
        ];
        move_down = [
          "<Down>"
          "<C-j>"
        ];
        # C-p older query, C-n newer query, mirroring fzf history recall.
        cycle_previous_query = "<C-p>";
        cycle_forward_query = "<C-n>";
        # Scroll the preview with C-Up/C-Down, leaving C-u/C-d free.
        preview_scroll_up = "<C-Up>";
        preview_scroll_down = "<C-Down>";
        # Close the picker with <C-c> as well as <Esc>, like the old fzf-lua split.
        close = [
          "<Esc>"
          "<C-c>"
        ];
      };
    };
  };

  # Restore fzf-lua multi-select (<C-a> select-all, <CR> open-or-quickfix, <C-t> open-all-in-tabs); see the module for why fff can't do this natively.
  programs.nixvim.extraFiles."lua/nix-meridian/fff-multiselect.lua".source =
    ../contrib/fff-multiselect.lua;
  # Show the pagination scrollbar on page 0 too, so an overflowing result list flags that there is more; see the module.
  programs.nixvim.extraFiles."lua/nix-meridian/fff-scrollbar.lua".source =
    ../contrib/fff-scrollbar.lua;
  # Highlight the file-picker query match case-insensitively, matching grep (fff's file renderer only highlights exact case); see the module.
  programs.nixvim.extraFiles."lua/nix-meridian/fff-match-highlight.lua".source =
    ../contrib/fff-match-highlight.lua;
  # Disable fff's live-grep -> filename "suggestion": a no-match grep shows "No results" instead of switching to file mode; see the module.
  programs.nixvim.extraFiles."lua/nix-meridian/fff-disable-grep-suggestion.lua".source =
    ../contrib/fff-disable-grep-suggestion.lua;
  programs.nixvim.extraConfigLua = ''
    require("nix-meridian/fff-multiselect").setup()
    require("nix-meridian/fff-scrollbar").setup()
    require("nix-meridian/fff-match-highlight").setup()
    require("nix-meridian/fff-disable-grep-suggestion").setup()
  '';

  # fff renders its own popup content; strip the global BadWhitespace trailing-whitespace
  # match (see home/apps/nixvim/default.nix) from its buffers so the red flag is not noise
  # there. Deferred so it runs after that BufEnter handler adds it, whatever the autocmd order.
  programs.nixvim.autoCmd = [
    {
      event = [ "BufEnter" ];
      pattern = "*";
      callback.__raw = ''
        function(args)
          if vim.startswith(vim.bo[args.buf].filetype, "fff_") then
            vim.schedule(function()
              if vim.api.nvim_buf_is_valid(args.buf) then
                vim.api.nvim_buf_call(args.buf, function()
                  vim.cmd("silent! syntax clear BadWhitespace")
                end)
              end
            end)
          end
        end
      '';
    }
  ];
}
