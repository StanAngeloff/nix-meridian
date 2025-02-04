{
  programs.nixvim.plugins.cmp = {
    enable = true;

    autoEnableSources = true;

    settings = {
      sources = [
        { name = "copilot.vim"; }
        { name = "nvim_lsp"; }
        { name = "treesitter"; }
        { name = "path"; }
        { name = "buffer"; }
        { name = "conventionalcommits"; }
      ];

      mapping.__raw = "cmp.mapping.preset.insert()";
    };
  };
}
