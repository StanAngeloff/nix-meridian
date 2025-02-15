{
  config,
  lib,
  pkgs,
  ...
}:
{
  programs.nixvim = {
    opts = {
      autoread = false;
      backup = true;
      backupcopy = "yes";
      backupdir = "${config.home.homeDirectory}/.local/state/nvim/backup/";
      colorcolumn = "+0";
      completeopt = "menuone,popup";
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
      langmap = (lib.concatStringsSep "," [ "ч`" "яq" "вw" "еe" "рr" "тt" "ъy" "уu" "иi" "оo" "пp" "ш[" "щ]" "аa" "сs" "дd" "фf" "гg" "хh" "йj" "кk" "лl" "зz" "ьx" "цc" "жv" "бb" "нn" "мm" "Ч~" "ЯQ" "ВW" "ЕE" "РR" "ТT" "ЪY" "УU" "ИI" "ОO" "ПP" "Ш{" "Щ}" "АA" "СS" "ДD" "ФF" "ГG" "ХH" "ЙJ" "КK" "ЛL" "ЗZ" "ѝX" "ЦC" "ЖV" "БB" "НN" "МM" "Ю|" "ю\\\\" ]);
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
      spelllang = [
        "en"
        "bg"
      ];
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
      updatetime = 100;
      viewoptions = "cursor,folds,slash,unix";
      virtualedit = "block";
      wildignore = [
        "*/.git/*"
        "**/node_modules/*"
      ];
      wildignorecase = true;
      wildmode = "list:longest,full";
      wrap = true;
      # See https://neovim.io/doc/user/options.html#'exrc'
      # Automatically execute .nvim.lua, .nvimrc, and .exrc files in the current directory, if the file is in the trust list.
      exrc = true;
      secure = true;
    };

    globals = {
      tmux_target = ".2";
      tmux_command = "r";
    };
  };
}
