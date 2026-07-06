{ pkgs, inputs, ... }:
let
  neovim-wrapped = pkgs.neovim-unwrapped.overrideAttrs (prev: {
    meta = (prev.meta or { }) // {
      maintainers = prev.maintainers or [ ];
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

  # Propagate EDITOR to systemd and graphical sessions via environment.d/,
  # not just shell sessions via hm-session-vars.sh.
  systemd.user.sessionVariables.EDITOR = "nvim";

  programs.nixvim = {
    enable = true;

    package = neovim-wrapped;

    # Only covers shell sessions (hm-session-vars.sh), not graphical ones (environment.d/).
    # Kept for TTY logins where the shell is not a child of the systemd user manager.
    defaultEditor = true;

    viAlias = true;
    vimAlias = true;
    vimdiffAlias = true;

    # NOTE: Don't re-use global packages as nixvim constructs its own instance of nixpkgs.
    #nixpkgs.useGlobalPackages = true;

    # Point nixvim's private nixpkgs instance at the flake input it already follows.
    # This makes the default explicit and silences the follows-mismatch warning; the revision is unchanged.
    nixpkgs.source = inputs.nixpkgs;

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
