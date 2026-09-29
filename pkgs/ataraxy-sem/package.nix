{
  lib,
  rustPlatform,
  fetchFromGitHub,
  pkg-config,
  gitMinimal,
  libgit2,
  openssl,
  versionCheckHook,
}:
# Ataraxy Labs' sem: entity-level diffs over tree-sitter grammars. Plannotator's code review runs it for its semantic-diff view.
# Named ataraxy-sem because nixpkgs' sem is Semaphore CI's command-line client; the binary is still bin/sem.
rustPlatform.buildRustPackage (finalAttrs: {
  pname = "ataraxy-sem";
  # The version Plannotator pins as PLANNOTATOR_SEM_VERSION; pkgs/plannotator/update.sh keeps the two in step.
  version = "0.8.0";

  src = fetchFromGitHub {
    owner = "Ataraxy-Labs";
    repo = "sem";
    tag = "v${finalAttrs.version}";
    hash = "sha256-X2S6BBb7YVur9iAaCzSNEmP296V2Yy3PK+QujNMSfsI=";
  };

  # The Cargo workspace and its Cargo.lock live under crates/.
  sourceRoot = "${finalAttrs.src.name}/crates";

  cargoHash = "sha256-XumNe/xOlOOepacgF+aheEZwzGIlakutlxLlzx0Qjwo=";

  cargoBuildFlags = [
    "--package"
    "sem-cli"
  ];
  cargoTestFlags = finalAttrs.cargoBuildFlags;

  nativeBuildInputs = [ pkg-config ];

  buildInputs = [
    libgit2
    openssl
  ];

  # The log command's tests build their fixture repositories with the git command.
  nativeCheckInputs = [ gitMinimal ];

  # The verify tests write their cache under ~/.cache/sem.
  preCheck = ''
    export HOME="$(mktemp -d)"
  '';

  # These run git with PATH set to /usr/bin:/bin only (tests/setup_regressions.rs), which the build sandbox does not have.
  checkFlags = [
    "--skip=setup_and_unsetup_use_git_path_for_linked_worktree_hooks"
    "--skip=setup_writes_absolute_external_and_labels_cached_diff"
    "--skip=unsetup_unsets_external_but_keeps_modified_wrapper"
    "--skip=unsetup_removes_owned_wrapper_when_external_points_to_it"
  ];

  # Link nixpkgs' libgit2 instead of the copy git2 vendors, as nixpkgs' cargo-generate and biome do.
  env.LIBGIT2_NO_VENDOR = 1;

  nativeInstallCheckInputs = [ versionCheckHook ];
  doInstallCheck = true;

  meta = {
    description = "Entity-level semantic diffs over tree-sitter grammars";
    homepage = "https://github.com/Ataraxy-Labs/sem";
    license = with lib.licenses; [
      mit
      asl20
    ];
    platforms = lib.platforms.linux;
    mainProgram = "sem";
  };
})
