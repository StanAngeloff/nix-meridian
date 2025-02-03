{
  programs.nixvim = {
    plugins.committia = {
      enable = true;

      settings = {
        open_only_vim_starting = 1; # If you use `vim-fugitive`, I recommend to set this value to `1`.
      };
    };

    extraConfigVim = ''
      let g:committia_hooks = {}
      function! g:committia_hooks.edit_open(info)
        setlocal spell
        if a:info.vcs ==# 'git' && getline(1) ==# ${"''"} | startinsert | endif
        imap <buffer><C-n> <Plug>(committia-scroll-diff-down-half)
        imap <buffer><C-p> <Plug>(committia-scroll-diff-up-half)
      endfunction
    '';
  };
}
