{
  lib,
  rustPlatform,
  fetchFromGitHub,
  # Build-time dependencies
  installShellFiles,
  makeWrapper,
  # Test-time dependencies
  pkg-config,
  git,
  libgit2,
  openssl,
  zlib,
}:
let
  # Claude Code ingests this skill as a prompt, verbatim, so it is pinned by content rather than by trust.
  # The source hash covers the file already, but it covers everything else too: without a separate pin,
  # a routine bump for a bug fix would carry any rewritten instructions along with it, silently.
  # postInstall checks this digest and fails the build instead, so changing what Claude is told stays a deliberate act.
  # Update it only after reading the upstream diff.
  skillSha256 = "484461677e18bc18abf5d10d9e37f45e73040418805812524cedf50430b5d2e8";
in
rustPlatform.buildRustPackage (finalAttrs: {
  pname = "git-lines";
  # Upstream tags nothing and its own version numbers disagree — Cargo.toml still reads 0.1.0 while
  # .claude-plugin/plugin.json claims 0.2.0 — so the commit is the only version worth trusting.
  version = "0.1.0-unstable-2025-11-26";

  src = fetchFromGitHub {
    owner = "Omegaice";
    repo = "git-lines";
    rev = "0651613b6d5237357c6d535cb9d5aa3fd4156b33";
    hash = "sha256-0qgDL9QsmkNVhzr6ynEmi4dzDBv96PXtb0WVh91mnzA=";
  };

  # Pins the whole vendored crate closure, not just this repository.
  cargoHash = "sha256-oXwPEgTKghquQi0VbAtLRMUETzyu36Ifj7xc3Nw9icU=";

  nativeBuildInputs = [
    installShellFiles
    makeWrapper
  ];

  # git2 is a development dependency only, used to build the end-to-end test fixtures;
  # its libgit2-sys build script needs pkg-config to find these libraries,
  # and the suite shells out to git the same way the binary does at runtime.
  nativeCheckInputs = [
    pkg-config
    git
  ];
  checkInputs = [
    libgit2
    openssl
    zlib
  ];

  postInstall = ''
    $out/bin/git-lines man > git-lines.1
    installManPage git-lines.1

    installShellCompletion --cmd git-lines \
      --bash <($out/bin/git-lines completions bash) \
      --fish <($out/bin/git-lines completions fish) \
      --zsh <($out/bin/git-lines completions zsh)

    echo "${skillSha256}  skills/git-lines/SKILL.md" | sha256sum -c -
    # Named file rather than the directory: anything upstream adds beside SKILL.md — scripts especially —
    # has to be listed here before it can reach Claude.
    install -Dm444 skills/git-lines/SKILL.md -t $out/share/claude-code/skills/git-lines/
  '';

  # git-lines reads the patch text `git diff` hands back, and its parser hard-codes git's default a/…b/ path prefixes.
  # Configuration that reshapes those prefixes makes it report nothing to stage rather than fail —
  # the worst outcome for a tool Claude drives unattended, since "no changes" reads as success. diff.mnemonicPrefix
  # (set in this configuration) turns them into i/…w/; noprefix and the srcPrefix/dstPrefix pair rewrite them just as thoroughly.
  #
  # GIT_CONFIG_* entries are honoured by every git process in the environment, so pinning them here
  # restores the canonical shape for git-lines alone, and leaves the prefixes you read at the terminal untouched.
  # Appended at the next free index so a caller's own entries survive.
  postFixup = ''
    wrapProgram $out/bin/git-lines --run '
      git_config_index="''${GIT_CONFIG_COUNT:-0}"

      override_git_config() {
        export "GIT_CONFIG_KEY_$git_config_index=$1"
        export "GIT_CONFIG_VALUE_$git_config_index=$2"
        git_config_index=$((git_config_index + 1))
      }

      override_git_config diff.mnemonicprefix false
      override_git_config diff.noprefix false
      override_git_config diff.srcprefix a/
      override_git_config diff.dstprefix b/

      export GIT_CONFIG_COUNT="$git_config_index"
    '
  '';

  meta = {
    description = "Non-interactive line-level git staging tool";
    homepage = "https://github.com/Omegaice/git-lines";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
    mainProgram = "git-lines";
  };
})
