{ inputs, pkgs, ... }:
let
  # Upstream ships OpenAI's prebuilt native binary (auto-updater disabled, bubblewrap on its PATH for Codex's own sandbox).
  codex = inputs.codex-cli-nix.packages.${pkgs.stdenv.hostPlatform.system}.default;
in
{
  home.packages = [ codex ];
}
