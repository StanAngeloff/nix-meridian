{
  config,
  pkgs,
  pkgs-unstable,
  ...
}:
{
  programs.nixvim = {
    plugins.markdown-preview = {
      enable = true;
      package = pkgs-unstable.vimPlugins.markdown-preview-nvim;

      settings = {
        browser = "${pkgs.brave}/bin/brave";
        theme = "light";
        refresh_slow = 1;
        markdown_css = builtins.toString (
          pkgs.replaceVars ../resources/markdown.css {
            markdowncss = builtins.readFile "${pkgs-unstable.vimPlugins.markdown-preview-nvim}/app/_static/markdown.css";
            fontsSerif = config.nix-meridian.fonts.serif.name;
            fontsSansSerif = config.nix-meridian.fonts.sansSerif.name;
            fontsMonospace = config.nix-meridian.fonts.monospace.name;
          }
        );
        preview_options = {
          mkit.__raw = ''
            { breaks = 1 }
          '';
          content_editable = 0;
          disable_filename = 0;
          disable_sync_scroll = 0;
          sync_scroll_type = "middle";
          hide_yaml_meta = 0;
        };
      };
    };
  };
}
