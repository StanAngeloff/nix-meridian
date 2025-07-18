{
  programs.fzf = {
    enable = true;
    enableZshIntegration = true;

    # NOTE: See home/apps/ripgrep/default.nix - additional configuration including ripgrep colors under fzf.
    # NOTE: See home/apps/nixvim/plugins/fzf-lua.nix - additional configuration including ripgrep colors under fzf.
    colors = {
      "fg" = "#f6f6f8";
      "fg+" = "#ffffff";
      "bg" = "-1";
      "bg+" = "#303030";
      "hl" = "#aaaa00:reverse";
      "hl+" = "#aaaa00:reverse";
      "info" = "#666666";
      "marker" = "#74ff74";
      "prompt" = "#00c4ff";
      "spinner" = "#c400c4";
      "pointer" = "#c400c4";
      "header" = "#666666";
      "gutter" = "-1";
      "border" = "#262626";
      "scrollbar" = "#666666";
      "label" = "#008888";
      "query" = "#f7f7f7";
    };

    defaultOptions =
      let
        bindOptions = {
          "ctrl-f" = "page-down";
          "ctrl-b" = "page-up";
          "ctrl-d" = "half-page-down";
          "ctrl-u" = "half-page-up";
        };
        bindOptionsAsString = builtins.concatStringsSep "," (
          builtins.attrValues (builtins.mapAttrs (key: value: "${key}:${value}") bindOptions)
        );
      in
      [
        "--ellipsis='…'"
        "--marker='▎'"
        "--pointer='▶'"
        "--prompt='→ '"
        "--scrollbar='│'"
        "--separator='─'"

        "--info='right'"
        "--layout=reverse"
        "--preview-window='border-sharp'"

        "--bind '${bindOptionsAsString}'"
      ];
  };
}
