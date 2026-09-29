{
  lib,
  writeShellApplication,
  bubblewrap,
  coreutils,
  findutils,
  gnupg,
  jq,
  libsecret,
  openssh,
  procps,
  tmux,
  pipewire,
  systemd,
  util-linux,
  wl-clipboard,
  xdg-utils,
  claude-code,
  # Keyring var names the secrets module injects into the bubble.
  keyringVariables ? [ "GH_TOKEN" ],
  # Subcommands that are not bubble modules, as { name, handler, description }; modules declare theirs in module.nix.
  subcommands ? [ ],
}:
# Builds `claude-bubble` by assembling bubble.sh (the skeleton) from the modules under modules/<name>/hooks.sh.
# Each hooks.sh defines <module>_<phase>() hook functions (hyphens become underscores, e.g. notifications_before_run); the assembler concatenates every hooks.sh into the skeleton's functions slot and generates the per-phase call lines.
# A hook is detected only when defined at column zero as `<name>() {`, so a typo'd name gets no call line and fails the build via shellcheck's SC2329 (function never invoked).
# Modules may also declare `grants` in module.nix ({ name, description, default ? false }): each becomes an accepted `--with-<name>`/`--without-<name>` launcher flag, consumed by the skeleton into the bubble_grants array that hooks branch on, and documented after Claude Code's own --help output.
# Modules may also declare `subcommands` in module.nix ({ name, handler, description }), as may the caller through the `subcommands` argument: `cc <name> <arguments…>` then execs the handler before any bubble machinery starts, and `cc -h` lists it.
# Two-pass substitution: pass 1 fills the slots, pass 2 fills every value placeholder (the skeleton's claudeBin plus each module.nix's substitutions) — builtins.replaceStrings never rescans replaced text, and the hook bodies carry value placeholders of their own.
# shellcheck (via writeShellApplication) gates the fully assembled script, so cross-module breakage fails the build.
let
  # Assembly order = bwrap argument order (later mounts layer over earlier ones). Hard edges:
  #  - system before nix and ssh (nix masks sockets inside its /nix bind; ssh binds its filtered ssh_config over a store path there);
  #  - home before every module that binds under $HOME (claude, profiles, git, gpg, ssh, github, tools, nvim, pnpm);
  #  - claude before profiles (profiles masks ~/.claude/profiles inside the ~/.claude bind);
  #  - xdg before gpg, ssh, clipboard and podman (their sockets re-expose into its tmpfs mask);
  #  - gpg before ssh (gpg's --dir creates the runtime gnupg directory the ssh socket binds into).
  moduleNames = [
    "system"
    "lifetime"
    "home"
    "xdg"
    "claude"
    "profiles"
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
      jq
      libsecret
      openssh
      procps
      tmux
      pipewire
      systemd
      util-linux
      wl-clipboard
      xdg-utils
      keyringVariables
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
    # Shared with the standalone profiles command, which prepends the same file (see modules/profiles/module.nix).
    logHelpers = builtins.readFile ./utilities/log.sh;
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
  # Names become case patterns in the launcher and words in a zsh array, so they are kept to lowercase words.
  subcommandList = map (
    subcommand:
    assert lib.assertMsg (
      builtins.match "[a-z][a-z-]*" subcommand.name != null
    ) "claude-bubble: subcommand name '${subcommand.name}' must be a lowercase word";
    subcommand
  ) (lib.concatMap (module: module.metadata.subcommands or [ ]) modules ++ subcommands);
  subcommandNames =
    let
      names = map (subcommand: subcommand.name) subcommandList;
    in
    assert lib.assertMsg (lib.unique names == names) "claude-bubble: duplicate subcommand name";
    names;
  # The launcher runs this only when the word is followed by at least one more argument (see bubble.sh).
  subcommandDispatch =
    "case \"$argument\" in\n"
    + lib.concatMapStrings (
      subcommand:
      "${subcommand.name}) exec ${lib.escapeShellArg subcommand.handler} \"\${args[@]:$((index + 1))}\" ;;\n"
    ) subcommandList
    + "esac";
  # Rendered after the bubble options. Spliced into a single-quoted shell string like grantsHelp, so descriptions must not contain single quotes.
  subcommandsHelp = lib.optionalString (subcommandList != [ ]) (
    "\nSubcommands (handled by claude-bubble before any session starts):\n"
    + lib.concatMapStrings (
      subcommand: "  ${subcommand.name} <command>\n        ${subcommand.description}\n"
    ) subcommandList
  );
  valueSubstitutions =
    lib.foldl' (accumulated: module: accumulated // (module.metadata.substitutions or { }))
      {
        claudeBin = lib.getExe claude-code;
        inherit
          grantNames
          defaultGrantInitializers
          grantsHelp
          subcommandDispatch
          subcommandsHelp
          ;
      }
      modules;

  # Loopback opener for programs that take a browser command; see modules/notifications/www-browser.sh.
  wwwBrowser = writeShellApplication {
    name = "claude-bubble-www-browser";
    runtimeInputs = [ xdg-utils ];
    text = builtins.readFile ./modules/notifications/www-browser.sh;
  };
in
writeShellApplication {
  name = "claude-bubble";
  runtimeInputs = lib.unique (
    [
      bubblewrap
      coreutils
      findutils # xargs, for parsing CLAUDE_BUBBLE_ARGS
    ]
    ++ lib.concatMap (module: module.metadata.runtimeInputs or [ ]) modules
  );
  text = substitute valueSubstitutions (substitute slotSubstitutions (builtins.readFile ./bubble.sh));
  # aliases.nix hands subcommandNames to initialize.zsh, whose session checks mirror the launcher's handoff rule;
  # wwwBrowser is the loopback opener for programs that take a browser command.
  passthru = { inherit subcommandNames wwwBrowser; };
}
