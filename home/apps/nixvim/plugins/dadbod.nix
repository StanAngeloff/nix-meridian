{ pkgs-unstable, ... }:
{
  programs.nixvim = {
    plugins = with pkgs-unstable; {
      vim-dadbod = {
        enable = true;
        package = vimPlugins.vim-dadbod;
      };

      vim-dadbod-ui = {
        enable = true;
        package = vimPlugins.vim-dadbod-ui;
      };

      vim-dadbod-completion = {
        enable = true;
        package = vimPlugins.vim-dadbod-completion;
      };
    };

    extraConfigLua = ''
      vim.g.db_ui_disable_mappings_sql = 1
      vim.g.db_ui_disable_mappings_javascript = 1
    '';
  };
}
