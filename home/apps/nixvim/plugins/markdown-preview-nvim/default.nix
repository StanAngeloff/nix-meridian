{
  config,
  lib,
  pkgs,
  pkgs-unstable,
  ...
}:
let
  upstream = pkgs-unstable.vimPlugins.markdown-preview-nvim;

  # Each name maps to ./markdown-it/<name>.js (required; the function inside
  # must be named after the file) and an optional ./markdown-it/<name>.css
  # sibling that gets concatenated onto the rendered preview's stylesheet.
  pluginNames = [
    "attrsPlugin"
    "fileRefPlugin"
    "githubAlertsPlugin"
    "indeterminateTaskPlugin"
    "rolesPlugin"
    "thinkingBlockPlugin"
  ];

  pluginJs = name: ./markdown-it + "/${name}.js";
  pluginCss =
    name:
    let
      p = ./markdown-it + "/${name}.css";
    in
    if builtins.pathExists p then p else null;

  pluginCssFiles = builtins.filter (p: p != null) (map pluginCss pluginNames);

  # Patch the upstream plugin's bundled index.js so each markdown-it plugin's
  # function definition is appended and chained onto md.use(...). The plugin's
  # bundle path includes a hash, hence the */pages/index.js glob.
  markdown-preview-nvim = upstream.overrideAttrs (
    final: prev: {
      postInstall =
        let
          useChain = lib.concatStringsSep ").use(" pluginNames;
          appendJs = lib.concatMapStringsSep "\n" (
            n: "cat ${pluginJs n} >> $out/app/out/_next/static/*/pages/index.js"
          ) pluginNames;
        in
        ''
          ${prev.postInstall or ""}

          grep -q ',this.md.use(' $out/app/out/_next/static/*/pages/index.js && \
            sed -i 's/,this.md.use(/,this.md.use(${useChain}).use(/' $out/app/out/_next/static/*/pages/index.js

          ${appendJs}
        '';
    }
  );

  # theme.css holds the global stuff (upstream markdown.css injection + font
  # overrides); each plugin's optional sibling .css is appended after.
  themeCss = pkgs.replaceVars ./theme.css {
    markdowncss = builtins.readFile "${upstream}/app/_static/markdown.css";
    fontsSerif = config.nix-meridian.fonts.serif.name;
    fontsSansSerif = config.nix-meridian.fonts.sansSerif.name;
    fontsMonospace = config.nix-meridian.fonts.monospace.name;
  };

  markdownCss = pkgs.runCommand "markdown-preview.css" { } ''
    cat ${themeCss} > $out
    ${lib.concatMapStringsSep "\n" (p: "printf '\\n' >> $out && cat ${p} >> $out") pluginCssFiles}
  '';

  preview = pkgs.writeShellApplication {
    name = "preview";
    runtimeInputs = [ pkgs.coreutils ];
    text = builtins.readFile (
      pkgs.replaceVars ./preview.sh {
        nvim = lib.getExe config.programs.nixvim.build.package;
      }
    );
  };
in
{
  home.packages = [ preview ];

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
        markdown_css = builtins.toString markdownCss;
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
