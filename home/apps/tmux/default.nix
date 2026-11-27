{
  config,
  pkgs,
  osConfig,
  ...
}:
let
  tmux = "${pkgs.tmux}/bin/tmux";

  # Debounced dim of the Claude Code idle status dot: bright green (unread) fades to dim green (read).
  #
  # The after-select-window hook launches this in the background with the just-selected window ID as $1.
  # After a short dwell it clears @claude-unread on that window's panes, but only if the window is STILL focused, so cycling past a window with Ctrl+Tab (which leaves before the dwell elapses) keeps the bright dot.
  dismissClaudeIdle = pkgs.writeShellScript "tmux-dismiss-claude-idle" ''
    expected="$1"
    sleep 2
    [ "$(${tmux} display-message -p -t "$expected" '#{window_active}')" = 1 ] || exit 0
    ${tmux} list-panes -t "$expected" -F '#{pane_id}' | while read -r pane_id; do
      ${tmux} set -pu -t "$pane_id" @claude-unread 2>/dev/null || true
    done
    ${tmux} refresh-client -S 2>/dev/null || true
  '';

  nameWindow = pkgs.writeShellScript "tmux-name-window" ''
    adjectives=(
      big old shy mad sad red hot cold cool calm
      bold dim dry fat fit flat glad grim keen kind
      lazy lean loud mean mild neat odd pale pink plum
      posh raw rich ripe rude slim slow smug soft sour
      tall tame thin tiny warm weak wide wild wise dull
    )
    animals=(
      ant ape bat bear bee boar bull cat cod cow
      crab crow deer dog dove duck eel elk ewe fish
      fly fox frog goat gull hare hawk hen hog jay
      koi lamb lark lion lynx mare mink mole moth mule
      newt owl ox pig pug ram rat seal slug swan
      toad vole wasp wolf worm wren yak
    )
    existing=$(${tmux} list-windows -F '#{window_name}' 2>/dev/null)
    for _ in 1 2 3 4 5 6 7 8 9 10; do
      name="$(shuf -n1 -e "''${adjectives[@]}")-$(shuf -n1 -e "''${animals[@]}")"
      echo "$existing" | grep -qxF "$name" || break
    done
    echo "$name"
  '';

  # Saves the keyword of a window name such as nix-meridian@feature-x[DOCS].
  saveWindowKeyword = pkgs.writeShellScript "tmux-save-window-keyword" ''
    exec ${pkgs.zsh}/bin/zsh -f -c 'source ${../claude-code/initialize.zsh} && _claude_save_window_keyword "$1"' tmux-save-window-keyword "$1"
  '';

  popupNvim = import ../../../modules/lib/popup-nvim.nix { inherit pkgs; };

  # Edits the note file $1, named by floats/scratch-note-float.sh, and removes it when left empty.
  scratchNote = pkgs.writeShellScript "tmux-scratch-note" ''
    note="$1"
    mkdir -p "$(dirname "$note")"
    ${popupNvim}/bin/popup-nvim "$note"
    if [ -f "$note" ] && ! grep -q '[^[:space:]]' "$note"; then
      rm -f "$note"
    fi
  '';

  # The floating pane scripts behind prefix C-g, G and C-n, sharing floats/popup-box.sh.
  # Floating panes move and resize from tmux 3.8 on, which is why tmux comes from nixpkgs-unstable (pkgs/overlays.nix).
  floatScript =
    name: file: runtimeInputs:
    pkgs.writeShellApplication {
      inherit name runtimeInputs;
      text =
        builtins.replaceStrings
          [ "@popupBox@" "@scratchNote@" ]
          [ "${./floats/popup-box.sh}" "${scratchNote}" ]
          (builtins.readFile file);
    };
  tigFloat = floatScript "tmux-tig-float" ./floats/tig-float.sh [
    pkgs.coreutils
    pkgs.tmux
  ];
  tigPath = floatScript "tmux-tig-path" ./floats/tig-path.sh [
    pkgs.coreutils
    pkgs.findutils
    pkgs.fzf
    pkgs.gnugrep
    pkgs.tmux
  ];
  scratchNoteFloat = floatScript "tmux-scratch-note-float" ./floats/scratch-note-float.sh [
    pkgs.coreutils
    pkgs.tmux
  ];

  # Runs the issue board script that issues-toggle.sh finds, behind prefix C-i and I.
  # The board reads the store through git and parses its issues with yq, so both come along.
  issuesBoard = pkgs.writeShellApplication {
    name = "tmux-issues-board";
    runtimeInputs = [
      pkgs.git
      pkgs.nodejs_24
      pkgs.yq-go
    ];
    text = ''
      exec node "$@"
    '';
  };
  issuesToggle = pkgs.writeShellApplication {
    name = "tmux-issues-toggle";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.git
      pkgs.tmux
    ];
    text = builtins.replaceStrings [ "@issuesBoard@" ] [ (pkgs.lib.getExe issuesBoard) ] (
      builtins.readFile ./issues-toggle.sh
    );
  };

  # The sidebar of every window behind prefix Tab (abilities/tmux.navigator.conf); the design is in navigator/control.py.
  navigator = pkgs.callPackage ./navigator/package.nix {
    links = import ../claude-code/footer-links.nix;
  };

  # Cleans what the copy bindings in tmux.conf copy in a Claude Code pane.
  claudeCopy = pkgs.callPackage ./claude-copy/package.nix { };

  # Right-click and Alt+right-click on a pane: tmux's own pane menu, pasted into pane-menu/stock.conf,
  # with Open and Copy Path entries first for the file or directory named under the pointer (pane-menu/file_under_pointer.py).
  fileUnderPointer = pkgs.callPackage ./pane-menu/package.nix { inherit claudeCopy; };
  stockPaneMenuBinding =
    key:
    let
      prefix = "bind-key  -T root ${key} ";
    in
    pkgs.lib.removePrefix prefix (
      pkgs.lib.findFirst (pkgs.lib.hasPrefix prefix) (throw "pane-menu/stock.conf has no ${key} binding")
        (pkgs.lib.splitString "\n" (builtins.readFile ./pane-menu/stock.conf))
    );
  # Alt+right-click is the menu alone; right-click opens the same menu unless a program in the pane reads the mouse.
  stockPaneMenu = stockPaneMenuBinding "M-MouseDown3Pane";
  stockPaneMenuCondition =
    let
      binding = stockPaneMenuBinding "MouseDown3Pane";
      menuSuffix = " { ${stockPaneMenu} }";
    in
    assert pkgs.lib.assertMsg (pkgs.lib.hasSuffix menuSuffix binding)
      "pane-menu/stock.conf: the right-click binding no longer ends in the Alt+right-click menu";
    pkgs.lib.removeSuffix menuSuffix binding;
  # The entries go between the menu's title and placement and its first item.
  stockPaneMenuHeader = ''display-menu -T "#[align=centre]#{pane_index} (#{pane_id})" -t = -x M -y M '';
  stockPaneMenuItems =
    assert pkgs.lib.assertMsg (pkgs.lib.hasPrefix stockPaneMenuHeader stockPaneMenu)
      "pane-menu/stock.conf: the pane menu no longer starts with its title and placement";
    pkgs.lib.removePrefix stockPaneMenuHeader stockPaneMenu;
  paneMenuWithFileEntries = builtins.concatStringsSep " ; " [
    ''run-shell -t = "${pkgs.lib.getExe fileUnderPointer} find --pane #{pane_id} --x=#{mouse_x} --y=#{mouse_y} --scroll=#{scroll_position} --height=#{pane_height} --path=#{q:pane_current_path} --hyperlink=#{q:mouse_hyperlink}"''
    (
      stockPaneMenuHeader
      + ''"#{?@file-under-pointer,Open #[underscore]#{=/-40/...:@file-under-pointer-label},-Open File}" o { run-shell -b -t = "${pkgs.lib.getExe fileUnderPointer} open --pane #{pane_id}" } ''
      + ''"#{?@file-under-pointer,Copy Path,-Copy Path}" y { run-shell -b -t = "${pkgs.lib.getExe fileUnderPointer} copy --pane #{pane_id} --client=#{q:client_name}" } ''
      + "'' "
      + stockPaneMenuItems
    )
  ];
  paneMenu = ''
    bind -n MouseDown3Pane ${stockPaneMenuCondition} { ${paneMenuWithFileEntries} }
    bind -n M-MouseDown3Pane { ${paneMenuWithFileEntries} }
  '';
  # Fails the build when tmux's own pane menus no longer match pane-menu/stock.conf, or the menus with the file entries don't load.
  paneMenuCheck =
    pkgs.runCommand "tmux-pane-menu-check"
      {
        nativeBuildInputs = [
          pkgs.diffutils
          pkgs.tmux
        ];
      }
      ''
        list_menus() {
          tmux -S "$TMPDIR/$1" -f "$2" start-server \; list-keys -T root MouseDown3Pane \; list-keys -T root M-MouseDown3Pane
        }
        if ! diff -u <(grep -v '^#' ${./pane-menu/stock.conf}) <(list_menus stock /dev/null); then
          echo "tmux ${pkgs.tmux.version} has changed its own pane menus: replace the bind-key lines in home/apps/tmux/pane-menu/stock.conf with the + lines above." >&2
          exit 1
        fi
        if [ "$(list_menus file-entries ${pkgs.writeText "tmux-pane-menu.conf" paneMenu} | grep -c '@file-under-pointer')" != 2 ]; then
          echo "The pane menus with the file entries do not load in tmux ${pkgs.tmux.version}." >&2
          exit 1
        fi
        touch "$out"
      '';
in
{
  programs.tmux = {
    enable = true;

    sensibleOnTop = true;

    aggressiveResize = true;
    baseIndex = 1;
    clock24 = true;
    escapeTime = 0;
    focusEvents = true;
    historyLimit = 102400;
    keyMode = "vi";
    mouse = true;
    prefix = "C-s";
    terminal = "tmux-256color";

    plugins = [ ];

    extraConfig = ''
      ${builtins.readFile ./claude-state.conf}
      ${
        let
          replacements = {
            "@claudeCopy@" = pkgs.lib.getExe claudeCopy;
            "@dismissClaudeIdle@" = "${dismissClaudeIdle}";
            "@machineName@" = osConfig.networking.hostName;
            "@nameWindow@" = "${nameWindow}";
            "@navigatorPlaceholder@" = "${navigator}/bin/tmux-navigator-placeholder";
            "@saveWindowKeyword@" = "${saveWindowKeyword}";
          };
        in
        builtins.replaceStrings (builtins.attrNames replacements) (builtins.attrValues replacements) (
          builtins.readFile ./tmux.conf
        )
      }
      ${builtins.replaceStrings
        [ "@tigFloat@" "@tigPath@" ]
        [ (pkgs.lib.getExe tigFloat) (pkgs.lib.getExe tigPath) ]
        (builtins.readFile ./abilities/tmux.tig.conf)
      }
      ${builtins.readFile ./abilities/tmux.nix-diff.conf}
      ${builtins.replaceStrings [ "@scratchNoteFloat@" ] [ (pkgs.lib.getExe scratchNoteFloat) ] (
        builtins.readFile ./abilities/tmux.scratch-note.conf
      )}
      ${builtins.replaceStrings [ "@issuesToggle@" ] [ (pkgs.lib.getExe issuesToggle) ] (
        builtins.readFile ./abilities/tmux.issues.conf
      )}
      ${builtins.replaceStrings
        [ "@navigator@" "@home@" ]
        [ (pkgs.lib.getExe navigator) config.home.homeDirectory ]
        (builtins.readFile ./abilities/tmux.navigator.conf)
      }
      ${paneMenu}
    '';
  };

  home.checks = [ paneMenuCheck ];
}
