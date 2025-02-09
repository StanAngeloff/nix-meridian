{
  imports = [
    ./base64.nix
    ./bufferline.nix
    ./caser.nix
    ./cmp.nix
    ./comment.nix
    ./committia.nix
    ./copilot.nix
    ./eunuch.nix
    ./fugitive.nix
    ./fzf.nix
    ./gitgutter.nix
    ./hexokinase.nix
    ./lsp.nix
    ./lspsaga.nix
    ./lualine.nix
    ./nerdtree.nix
    ./nvim-autopairs.nix
    ./repeat.nix
    ./ripgrep.nix
    ./schemastore.nix
    ./sleuth.nix
    ./surround.nix
    ./targets.nix
    ./treesitter.nix
    ./treesitter-context.nix
    ./treesitter-textobjects.nix
    ./ts-error-translator.nix
    ./undotree.nix
    ./unimpaired.nix
    ./zend55.nix
  ];

  # Don't enable `plugins.web-devicons` automatically because other plugins are enabled.
  programs.nixvim.plugins.web-devicons.enable = false;
}
