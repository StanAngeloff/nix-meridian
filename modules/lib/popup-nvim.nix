{
  pkgs,
  lib ? pkgs.lib,
}:
let
  common = import ../../home/apps/nixvim/keymaps/common.nix;

  modePrefix = m: builtins.substring 0 1 m;

  keymapToVimLines =
    {
      key,
      modes,
      action,
      ...
    }:
    map (m: "${modePrefix m}noremap ${key} ${action}") modes;

  keymapLines = lib.concatStringsSep "\n" (lib.concatMap keymapToVimLines common.keymaps);

  initVim = pkgs.writeText "popup-nvim-init.vim" ''
    let mapleader = '${common.leader}'
    set noswapfile nobackup noundofile
    highlight Normal guibg=#081018 ctermbg=NONE
    set laststatus=0 showtabline=0 signcolumn=no nonumber norelativenumber cmdheight=0
    let &fillchars = 'eob: '
    set textwidth=0 wrapmargin=0 wrap linebreak breakindent
    ${keymapLines}
    inoremap <Esc> <Cmd>silent! write <Bar> quit!<CR>
    nnoremap <Esc> <Cmd>silent! write <Bar> quit!<CR>
    nnoremap <CR> <Cmd>silent! write<CR>
    nnoremap q <Cmd>silent! write <Bar> quit!<CR>
    autocmd VimLeavePre * silent! write
  '';
in
pkgs.writeShellScriptBin "popup-nvim" ''
  insert_flag=()
  if [ ! -f "$1" ] || ! grep -q '[^[:space:]]' "$1"; then
    insert_flag=(-c startinsert)
  fi
  exec nvim -u ${initVim} \
    "''${insert_flag[@]}" \
    "$1"
''
