let
  # List of packages from the npm registry I use often, but can't be bothered to install them system-wide. ( ͡° ͜ʖ ͡°)
  # Having them aliased to "@latest" also keeps them up-to-date automatically on each use.
  npm_registry_apps = {
    amp = "@sourcegraph/amp";
    claude = "@anthropic-ai/claude-code";
  };
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
  // builtins.mapAttrs (name: pkg: "pnpm --silent dlx ${pkg}@latest") npm_registry_apps;
}
