{
  lib,
  writeShellApplication,
  bubblewrap,
  coreutils,
  gnupg,
  libsecret,
  tmux,
  pipewire,
  util-linux,
  wl-clipboard,
  claude-code,
  # Keyring var names the secrets module injects into the bubble.
  secretVars ? [ "GH_TOKEN" ],
}:
# Builds `claude-bubble` by assembling bubble.sh (the skeleton) from the modules under modules/<name>/hooks.sh.
# Each hooks.sh defines <module>_<phase>() hook functions (hyphens become underscores, e.g. notifications_before_run); the assembler concatenates every hooks.sh into the skeleton's functions slot and generates the per-phase call lines.
# A hook is detected only when defined at column zero as `<name>() {`, so a typo'd name gets no call line and fails the build via shellcheck's SC2329 (function never invoked).
# Modules may also declare `grants` in module.nix ({ name, description, default ? false }): each becomes an accepted `--with-<name>`/`--without-<name>` launcher flag, consumed by the skeleton into the bubble_grants array that hooks branch on, and documented after Claude Code's own --help output.
# Two-pass substitution: pass 1 fills the slots, pass 2 fills every value placeholder (the skeleton's claudeBin plus each module.nix's substitutions) — builtins.replaceStrings never rescans replaced text, and the hook bodies carry value placeholders of their own.
# shellcheck (via writeShellApplication) gates the fully assembled script, so cross-module breakage fails the build.
let
  # Assembly order = bwrap argument order (later mounts layer over earlier ones). Hard edges:
  #  - home before every module that binds under $HOME (claude, git, gpg, ssh, github, nvim, pnpm);
  #  - xdg before gpg, ssh, clipboard and podman (their sockets re-expose into its tmpfs mask);
  #  - gpg before ssh (gpg's --dir creates the runtime gnupg directory the ssh socket binds into).
  moduleNames = [
    "system"
    "home"
    "xdg"
    "claude"
    "nix"
    "git"
    "gpg"
    "ssh"
    "clipboard"
    "github"
    "secrets"
    "tools"
    "nvim"
    "pnpm"
    "desktop"
    "podman"
    "notifications"
  ];
  phaseNames = [
    "prepare"
    "mount"
    "environment"
    "before-run"
    "after-run"
    "cleanup"
  ];

  # Fixed argument set every module.nix is called with; modules pattern-match what they need.
  moduleArguments = {
    inherit
      lib
      writeShellApplication
      coreutils
      gnupg
      libsecret
      tmux
      pipewire
      util-linux
      wl-clipboard
      secretVars
      ;
  };
  modules = map (
    name:
    let
      directory = ./modules + "/${name}";
    in
    {
      inherit name directory;
      hooksText = builtins.readFile (directory + "/hooks.sh");
      metadata =
        if builtins.pathExists (directory + "/module.nix") then
          import (directory + "/module.nix") moduleArguments
        else
          { };
    }
  ) moduleNames;

  underscorize = lib.replaceStrings [ "-" ] [ "_" ];
  hookName = module: phaseName: "${underscorize module.name}_${underscorize phaseName}";
  definesHook =
    module: phaseName: lib.hasInfix "\n${hookName module phaseName}() {" ("\n" + module.hooksText);

  # All hook definitions, in module order, each headed by a provenance banner.
  moduleFunctions = lib.concatMapStrings (module: ''
    ### module: ${module.name}
    ${module.hooksText}
  '') modules;

  # One call line per module that defines the phase's hook, in module order.
  concatCalls =
    phaseName:
    lib.concatMapStrings (
      module: lib.optionalString (definesHook module phaseName) "${hookName module phaseName}\n"
    ) modules;

  # "before-run" -> "beforeRun": placeholders are camelCase per the build-time substitution convention.
  camelize =
    hyphenated:
    let
      words = lib.splitString "-" hyphenated;
      capitalize =
        word:
        lib.toUpper (builtins.substring 0 1 word) + builtins.substring 1 (builtins.stringLength word) word;
    in
    builtins.head words + lib.concatMapStrings capitalize (builtins.tail words);

  substitute =
    substitutions: text:
    builtins.replaceStrings (map (name: "@${name}@") (
      builtins.attrNames substitutions
    )) (builtins.attrValues substitutions) text;

  slotSubstitutions = {
    inherit moduleFunctions;
  }
  // lib.listToAttrs (
    map (phaseName: {
      name = "${camelize phaseName}Calls";
      value = concatCalls phaseName;
    }) phaseNames
  );
  grantList = lib.concatMap (module: module.metadata.grants or [ ]) modules;
  grantNames = lib.concatStringsSep " " (map (grant: grant.name) grantList);
  defaultGrantInitializers = lib.concatMapStrings (
    grant: lib.optionalString (grant.default or false) "bubble_grants[${grant.name}]=1\n"
  ) grantList;
  # Rendered after Claude Code's own --help output. Spliced into a single-quoted shell string, so descriptions must not contain single quotes (the build fails on one).
  grantsHelp = lib.optionalString (grantList != [ ]) (
    "\nBubble options (consumed by claude-bubble; never passed to Claude Code):\n"
    + lib.concatMapStrings (
      grant:
      "  --with-${grant.name}, --without-${grant.name}\n        ${grant.description} (default: "
      + (if grant.default or false then "on" else "off")
      + ")\n"
    ) grantList
  );
  valueSubstitutions =
    lib.foldl' (accumulated: module: accumulated // (module.metadata.substitutions or { }))
      {
        claudeBin = lib.getExe claude-code;
        inherit grantNames defaultGrantInitializers grantsHelp;
      }
      modules;
in
writeShellApplication {
  name = "claude-bubble";
  runtimeInputs = lib.unique (
    [
      bubblewrap
      coreutils
    ]
    ++ lib.concatMap (module: module.metadata.runtimeInputs or [ ]) modules
  );
  text = substitute valueSubstitutions (substitute slotSubstitutions (builtins.readFile ./bubble.sh));
}
