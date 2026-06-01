{ inputs, system }:
final: prev: {
  curlconverter = final.callPackage ./curlconverter/package.nix { };
  ghostty = final.callPackage ./ghostty/overlay.nix { ghostty = prev.ghostty; };
  mcp-server-trello = final.callPackage ./mcp-server-trello/package.nix { };
  mutter = final.callPackage ./mutter/overlay.nix { mutter = prev.mutter; };
  mcporter = final.callPackage ./mcporter/package.nix { };
  n8n-cli = final.callPackage ./n8n-cli/package.nix { };
  otter-mcp = final.callPackage ./otter-mcp/package.nix { };
  slack-mcp-server = final.callPackage ./slack-mcp-server/package.nix { };
  tig = final.callPackage ./tig/overlay.nix { tig = prev.tig; };
  voxize = final.callPackage ./voxize/package.nix { };
}
