{
  lib,
  stdenv,
  fetchFromGitHub,
  rustPlatform,
  withFzf ? true,
  fzf,
  installShellFiles,
  libiconv,
}:

# Building from source as the latest release (v0.9.8) does not contain https://github.com/ajeetdsouza/zoxide/pull/1027 "--base-dir" support.
#
# See https://github.com/NixOS/nixpkgs/blob/nixos-25.11/pkgs/by-name/zo/zoxide/package.nix
rustPlatform.buildRustPackage rec {
  pname = "zoxide";
  version = "main@{2025-09-23T12:00:00Z}";

  src = fetchFromGitHub {
    owner = "ajeetdsouza";
    repo = "zoxide";
    rev = builtins.replaceStrings [ "@" "{" "}" ":" ] [ "%40" "%7B" "%7D" "%3A" ] version;
    hash = "sha256-G83fRrYck5YJA1LdTqUskPDQMb8XweyHZ+PxkrdDZng=";
  };

  nativeBuildInputs = [ installShellFiles ];

  buildInputs = lib.optionals stdenv.hostPlatform.isDarwin [ libiconv ];

  postPatch = lib.optionalString withFzf ''
    substituteInPlace src/util.rs \
      --replace '"fzf"' '"${fzf}/bin/fzf"'
  '';

  cargoHash = "sha256-UjDy4SKfGep7r9DnMjb1BSytauyYevzHamkJMkfbMKQ=";

  postInstall = ''
    installManPage man/man*/*
    installShellCompletion --cmd zoxide \
      --bash contrib/completions/zoxide.bash \
      --fish contrib/completions/zoxide.fish \
      --zsh contrib/completions/_zoxide
  '';

  meta = with lib; {
    license = with licenses; [ mit ];
    mainProgram = "zoxide";
  };
}
