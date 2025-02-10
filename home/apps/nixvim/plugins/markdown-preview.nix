{ pkgs, ... }:
{
  programs.nixvim = {
    extraPlugins = with pkgs.vimPlugins; [
      markdown-preview-nvim
    ];

    globals = {
      mkdp_browser = "${pkgs.google-chrome}/bin/google-chrome-stable";
      mkdp_theme = "light";
      mkdp_refresh_slow = 1;

      mkdp_preview_options = {
        "mkit" = {
          "breaks" = 1;
        };
        "katex" = { };
        "uml" = { };
        "maid" = { };
        "disable_sync_scroll" = 0;
        "sync_scroll_type" = "middle";
        "hide_yaml_meta" = 1;
        "sequence_diagrams" = { };
        "flowchart_diagrams" = { };
        "content_editable" = false;
        "disable_filename" = 0;
        "toc" = { };
      };
    };
  };
}
