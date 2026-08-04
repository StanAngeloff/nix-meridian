# Marketplaces Claude Code may install plugins from, and which of their plugins load in every session.
# Projected into ~/.claude/settings.json by settings.nix: the keys become extraKnownMarketplaces entries,
# and each "<plugin>@<marketplace>" pair becomes an enabledPlugins entry.
#
# Deliberately unpinned, though Claude Code does accept a forty-character commit SHA per plugin.
# Skills are prose that improves upstream, FORCE_AUTOUPDATE_PLUGINS (env.nix) already opts this machine into tracking that,
# and one marketplace below is ours, where a SHA bump per skill edit would be pure friction.
# What reproduces across machines is therefore the trusted set — which marketplaces may supply plugins, and which are
# enabled — not a commit.
#
# Plugins are nested under the marketplace that supplies them because a plugin does not exist apart from it, and because
# the identifiers Claude Code wants are then derived rather than restated. A marketplace with no plugins is trusted but
# contributes nothing to a session.
{
  claude-skills = {
    repo = "StanAngeloff/claude-skills";
    plugins = [ "sparks" ];
  };

  superpowers-marketplace = {
    repo = "obra/superpowers-marketplace";
    plugins = [ "superpowers" ];
  };

  # ast-grep/claude-skill, the repository this marketplace's own manifest advertises, is a stale name that redirects here.
  ast-grep-marketplace = {
    repo = "ast-grep/agent-skill";
    plugins = [ "ast-grep" ];
  };
}
