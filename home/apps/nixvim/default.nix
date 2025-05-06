{ pkgs-unstable, ... }:
let
  neovim-unwrapped = pkgs-unstable.neovim-unwrapped.overrideAttrs (previousAttrs: {
    meta = (previousAttrs.meta or { }) // {
      maintainers = previousAttrs.maintainers or [ ];
    };
  });
in
{
  imports = [
    ./abbreviations.nix
    ./commands.nix
    ./issues.nix
    ./keymaps.nix
    ./options.nix
    ./plugins
  ];

  programs.neovim = {
    # All Home Manager options are mirrored by nixvim.
  };

  programs.nixvim = {
    enable = true;

    package = neovim-unwrapped;

    defaultEditor = true;

    viAlias = true;
    vimAlias = true;
    vimdiffAlias = true;

    # NOTE: Don't re-use global packages as nixvim constructs its own instance of nixpkgs.
    #nixpkgs.useGlobalPackages = true;

    colorscheme = "vim-zend55";

    globals = {
      # Syntax highlight shell scripts as per POSIX, not the original Bourne shell which very few use.
      is_posix = 1;
    };

    editorconfig.enable = true;

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
      {
        event = [ "BufEnter" ];
        pattern = "*";
        callback.__raw = ''
          function()
            if vim.bo.buftype:find("terminal") == nil then
              -- Highlight trailing whitespace after the colour scheme has loaded.
              vim.cmd("syntax match BadWhitespace /\\s\\+$\\| \\+\\ze\\t/ containedin=ALL")
              vim.cmd("highlight BadWhitespace guibg=#ff0000")
            end
          end
        '';
      }
    ];
  };
}
