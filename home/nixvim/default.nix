{ config, lib, pkgs, ... }:
{
  imports = [
    ./plugins
    ./keymaps.nix
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

    opts = {
      backup = true;
      backupcopy = "yes";
      backupdir = "${config.home.homeDirectory}/.local/state/nvim/backup/";
      colorcolumn = "+0";
      completeopt = "menuone,noselect";
      cursorline = true;
      diffopt = "internal,filler,closeoff,linematch:60";
      display = "uhex,lastline";
      expandtab = true;
      fileformats = "unix,mac,dos";
      fillchars = "vert:│,fold:-";
      foldlevelstart = 99;
      foldmethod = "indent";
      formatoptions = "qrn1lo";
      history = 10000;
      ignorecase = true;
      infercase = false;
      langmap = (lib.concatStringsSep "," [
	"ч`" "яq" "вw" "еe" "рr" "тt" "ъy" "уu" "иi" "оo" "пp" "ш[" "щ]" "аa" "сs" "дd" "фf" "гg" "хh" "йj" "кk" "лl" "зz" "ьx" "цc" "жv" "бb" "нn" "мm" "Ч~" "ЯQ" "ВW" "ЕE" "РR" "ТT" "ЪY" "УU" "ИI" "ОO" "ПP" "Ш{" "Щ}" "АA" "СS" "ДD" "ФF" "ГG" "ХH" "ЙJ" "КK" "ЛL" "ЗZ" "ѝX" "ЦC" "ЖV" "БB" "НN" "МM" "Ю|" "ю\\\\"
      ]);
      laststatus = 3;
      lazyredraw = true;
      linebreak = true;
      listchars = "tab:→ ,eol:↵,extends:❯,precedes:❮,trail:␣";
      matchpairs = "(:),{:},[:],<:>";
      matchtime = 1;
      maxmempattern = 80000;
      mouse = "a";
      mousehide = true;
      relativenumber = true;
      scrolloff = 120;
      shell = "${pkgs.bash}/bin/bash";
      shiftround = true;
      shiftwidth = 2;
      shortmess = "aoOtTAI";
      showbreak = "┅";
      showtabline = 2;
      signcolumn = "auto:2";
      smartcase = true;
      softtabstop = 2;
      spell = true;
      spelllang = [ "en" "bg" ];
      switchbuf = "usetab,newtab";
      tabstop = 2;
      termguicolors = true;
      textwidth = 120;
      timeoutlen = 325;
      title = true;
      titlestring = "%t%( %M%)%( (%{expand(\"%:p:h\")})%)%( %a%)";
      ttimeoutlen = 10;
      undofile = true;
      undolevels = 2000;
      updatetime = 300;
      viewoptions = "cursor,folds,slash,unix";
      virtualedit = "block";
      wildignore = [ "*/.git/*" "**/node_modules/*" ];
      wildignorecase = true;
      wildmode = "list:longest,full";
      wrap = true;
      # See https://neovim.io/doc/user/options.html#'exrc'
      # Automatically execute .nvim.lua, .nvimrc, and .exrc files in the current directory, if the file is in the trust list.
      exrc = true;
      secure = true;
    };

    globals = {
      # Syntax highlight shell scripts as per POSIX, not the original Bourne shell which very few use.
      is_posix = 1;
    };

    autoGroups.views = { clear = true; };

    autoCmd = [
      {
        event = [ "BufRead" ];
        pattern = "*";
        group = "views";
        callback = { __raw = ''
          function()
            if vim.fn.expand("%") ~= "" and vim.bo.buftype:find("nofile") == nil then
              vim.cmd("silent! loadview")
            end
          end
        ''; };
      }
      {
        event = [ "BufWritePost" ];
        pattern = "*";
        group = "views";
        callback = { __raw = ''
          function()
            if vim.fn.expand("%") ~= "" and vim.bo.buftype:find("nofile") == nil then
              vim.cmd("mkview")
            end
          end
        ''; };
      }
      # Open help windows on the right in a vertical split, credits @EvanPurkhiser.
      {
        event = [ "FileType" ];
        pattern = "help";
        callback = { __raw = ''
          function()
            vim.cmd "wincmd L"
            vim.keymap.set("n", "q", ":bwipeout<CR>", { buffer = true, silent = true })
          end
        ''; };
      }
      # Highlight trailing whitespace after the colour scheme has loaded.
      {
        event = [ "BufEnter" ];
        pattern = "*";
        callback = { __raw = ''
          function()
            if vim.bo.buftype:find("terminal") == nil then
              vim.cmd("syntax match BadWhitespace /\\s\\+$\\| \\+\\ze\\t/ containedin=ALL")
              vim.cmd("highlight BadWhitespace guibg=#ff0000")
            end
          end
        ''; };
      }
    ];
  };

  # Allow unfree packages
  nixpkgs.config.allowUnfree = true;
}
