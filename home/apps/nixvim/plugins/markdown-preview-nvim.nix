{
  config,
  lib,
  pkgs,
  pkgs-unstable,
  ...
}:
let
  plugins = [
    ../resources/markdown-preview-nvim/fileRefPlugin.js
    ../resources/markdown-preview-nvim/githubAlertsPlugin.js
    ../resources/markdown-preview-nvim/mentionsPlugin.js
    ../resources/markdown-preview-nvim/thinkingBlockPlugin.js
  ];

  # names like "mentionsPlugin", "fileRefPlugin"
  pluginNames = map (p: lib.removeSuffix ".js" (builtins.baseNameOf p)) plugins;
  # ".use(mentionsPlugin).use(fileRefPlugin)" minus the leading dot (we add it in sed)
  pluginUseChain = builtins.concatStringsSep ").use(" pluginNames;
  # commands to append each plugin file to index.js
  appendPlugins = builtins.concatStringsSep "\n" (
    map (p: "cat ${p} >> $out/app/out/_next/static/*/pages/index.js") plugins
  );

  markdown-preview-nvim = pkgs-unstable.vimPlugins.markdown-preview-nvim.overrideAttrs (
    final: prev: {
      postInstall = ''
        ${prev.postInstall or ""}

        grep -q ',this.md.use(' $out/app/out/_next/static/*/pages/index.js && \
          sed -i 's/,this.md.use(/,this.md.use(${pluginUseChain}).use(/' $out/app/out/_next/static/*/pages/index.js

        ${appendPlugins}
      '';
    }
  );
in
{
  programs.nixvim = {
    plugins.markdown-preview = {
      enable = true;
      package = markdown-preview-nvim;

      settings = {
        filetypes = [
          "markdown"
          "chat"
        ];

        browser = "${pkgs.brave}/bin/brave";
        theme = "light";
        refresh_slow = 1;
        markdown_css = builtins.toString (
          pkgs.replaceVars ../resources/markdown-preview-nvim/markdown.css {
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
