{
  programs.nixvim.extraConfigLua = ''
    -- See * https://github.com/neovim/neovim/issues/32660#issuecomment-2692738191
    --     * https://github.com/neovim/neovim/pull/33145
    vim.g._ts_force_sync_parsing = true
  '';
}
