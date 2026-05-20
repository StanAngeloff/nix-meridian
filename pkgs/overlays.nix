{
  inputs,
  system,
  pkgs-unstable,
}:
final: prev: {
  ghostty = final.callPackage ./ghostty/overlay.nix {
    ghostty = inputs.ghostty-flake.packages.${system}.default;
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
}
