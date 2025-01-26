{
  imports = [
    ./plugins
    ./commands.nix
    ./keymaps.nix
    ./options.nix
  ];

  home.sessionVariables = {
    # NOTE: using programs.nixvim.defaultEditor should suffice, however it doesn't appear to be working.
    EDITOR = "nvim";
  };

  programs.neovim = {
    # All options are mirrored by nixvim.
  };

  programs.nixvim = {
    enable = true;

    defaultEditor = true;
    viAlias = true;
    vimAlias = true;

    # NOTE: This option is available in nixvim-unstable.
    #nixpkgs.useGlobalPackages = true;

    colorscheme = "vim-zend55";

    globals = {
      # Syntax highlight shell scripts as per POSIX, not the original Bourne shell which very few use.
      is_posix = 1;
    };

    autoGroups.views = {
      clear = true;
    };

    autoCmd = [
      {
        event = [ "BufRead" ];
        pattern = "*";
        group = "views";
        callback.__raw = ''
          function()
            if vim.fn.expand("%") ~= "" and vim.bo.buftype:find("nofile") == nil then
              vim.cmd("silent! loadview")
            end
          end
        '';
      }
      {
        event = [ "BufWritePost" ];
        pattern = "*";
        group = "views";
        callback.__raw = ''
          function()
            if vim.fn.expand("%") ~= "" and vim.bo.buftype:find("nofile") == nil then
              vim.cmd("mkview")
            end
          end
        '';
      }
      # Open help windows on the right in a vertical split, credits @EvanPurkhiser.
      {
        event = [ "FileType" ];
        pattern = "help";
        callback.__raw = ''
          function()
            vim.cmd "wincmd L"
            vim.keymap.set("n", "q", ":bwipeout<CR>", { buffer = true, silent = true })
          end
        '';
      }
      # Highlight trailing whitespace after the colour scheme has loaded.
      {
        event = [ "BufEnter" ];
        pattern = "*";
        callback.__raw = ''
          function()
            if vim.bo.buftype:find("terminal") == nil then
              vim.cmd("syntax match BadWhitespace /\\s\\+$\\| \\+\\ze\\t/ containedin=ALL")
              vim.cmd("highlight BadWhitespace guibg=#ff0000")
            end
          end
        '';
      }
    ];
  };

  # Allow unfree packages
  nixpkgs.config.allowUnfree = true;
}
