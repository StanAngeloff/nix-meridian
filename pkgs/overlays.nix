{ inputs, system }:
final: prev: {
  # nixfmt: off
  curlconverter = final.callPackage ./curlconverter/package.nix { };
  infonotary-ca = final.callPackage ./infonotary-ca/package.nix { };
  infonotary-idprime = final.callPackage ./infonotary-idprime/package.nix { };
  infonotary-client-software = final.libsForQt5.callPackage ./infonotary-client-software/package.nix { };
  infonotary-client-software-fhs = final.callPackage ./infonotary-client-software-fhs/package.nix { };
  heidisql = final.qt6Packages.callPackage ./heidisql/package.nix { };
  ghostty = final.callPackage ./ghostty/overlay.nix { ghostty = prev.ghostty; };
  git-lines = final.callPackage ./git-lines/package.nix { };
  mcp-server-trello = final.callPackage ./mcp-server-trello/package.nix { };
  mutter = final.callPackage ./mutter/overlay.nix { mutter = prev.mutter; };
  mcporter = final.callPackage ./mcporter/package.nix { };
  n8n-cli = final.callPackage ./n8n-cli/package.nix { };
  slack-mcp-server = final.callPackage ./slack-mcp-server/package.nix { };
  stampit-local-services = final.callPackage ./stampit-local-services/package.nix { };
  tesseract5 = final.callPackage ./tesseract/overlay.nix { tesseract = prev.tesseract5; };
  tesseract = final.tesseract5;
  tig = final.callPackage ./tig/overlay.nix { tig = prev.tig; };
  voxize = final.callPackage ./voxize/package.nix { };
  xsel = final.callPackage ./xsel/overlay.nix { xsel = prev.xsel; };
  # nixfmt: on, as: statements
}
