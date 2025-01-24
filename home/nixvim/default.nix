{
  imports = [
    ./plugins
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
      expandtab = true;
      shiftwidth = 2;
    };
  };
}
