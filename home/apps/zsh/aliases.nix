let
  # List of packages from the npm registry I use often, but can't be bothered to install them system-wide. ( ͡° ͜ʖ ͡°)
  # Having them aliased to "@latest" also keeps them up-to-date automatically on each use.
  npm_registry_apps = {
    amp = {
      package = "@sourcegraph/amp";
    };
    claude = {
      package = "@anthropic-ai/claude-code";
      env = {
        DISABLE_AUTOUPDATER = 1;
        DISABLE_INSTALLATION_CHECKS = 1;
        FORCE_AUTOUPDATE_PLUGINS = 1;
        USE_BUILTIN_RIPGREP = 0;
      };
    };
  };

  # Builds an alias string for an npm_registry_apps entry.
  # Prepends "KEY=value …" pairs when an `env` attrset is present.
  mkNpmAlias =
    name: cfg:
    let
      envPrefix =
        if cfg ? env then
          builtins.concatStringsSep " " (
            builtins.attrValues (builtins.mapAttrs (k: v: "${k}=${builtins.toString v}") cfg.env)
          )
          + " "
        else
          "";
    in
    "${envPrefix}pnpm --silent dlx ${cfg.package}@latest";
in
{
  programs.zsh.shellAliases = {
    g = "git";
    ll = "eza --long --all --mounts";
    open = "xdg-open";
    t = "tig status";
    v = "nvim -p";
    vim = "nvim -p";
  }
  // builtins.mapAttrs mkNpmAlias npm_registry_apps;
}
