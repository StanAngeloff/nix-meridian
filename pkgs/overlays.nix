{
  inputs,
  system,
  pkgs-unstable,
}:
final: prev: {
  ghostty = final.callPackage ./ghostty/overlay.nix {
    ghostty = pkgs-unstable.ghostty;
  };
  curlconverter = final.callPackage ./curlconverter/package.nix { };
  mcporter = final.callPackage ./mcporter/package.nix { };
  n8n-cli = final.callPackage ./n8n-cli/package.nix { };
  mcp-server-trello = final.callPackage ./mcp-server-trello/package.nix { };
  otter-mcp = final.callPackage ./otter-mcp/package.nix {
    python313 = pkgs-unstable.python313;
  };
  slack-mcp-server = final.callPackage ./slack-mcp-server/package.nix { };
  tig = final.callPackage ./tig/overlay.nix {
    tig = prev.tig;
  };
  # nixpkgs-25.11 ships python313Packages.openai 2.7.2, but voxize monkey-patches openai._streaming.Stream.__stream__
  # against the 2.10+ API that introduced Stream._options. 2.7.2 has no such attribute, so the patch raises
  # AttributeError on the first SSE event.
  #
  # We use pkgs-unstable.callPackage (not final.callPackage with a python313 override) so that every dependency —
  # Python interpreter, pygobject3, gtk4, glib, gobject-introspection, wrapGAppsHook4 — comes from the same channel.
  # Mixing channels causes GI_TYPELIB_PATH to list stable glib typelibs before unstable ones; pygobject3 from unstable
  # then fails to resolve GObject properties against the stale Gio-2.0.typelib (symptom: "doesn't support property
  # 'application_id'" on Gtk.Application subclasses).
  voxize = pkgs-unstable.callPackage ./voxize/package.nix { };
}
