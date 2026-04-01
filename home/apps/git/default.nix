{ lib, ... }:
{
  programs.git = {
    enable = true;
    lfs.enable = true;

    signing = {
      key = "595EA753";
      signByDefault = true;
    };

    # Git configuration https://git-scm.com/docs/git-config
    settings = {
      user = {
        name = "Stan Angeloff";
        email = "stanimir@angeloff.name";
      };

      github = {
        user = "StanAngeloff";
      };

      alias =
        let
          gitLogFormat = "%C(red)%h%C(reset) -%C(yellow)%d%C(reset) %s %C(green)%cr (%cd) %C(blue)%an%C(reset) ▸ %C(cyan)%cn%C(reset)";
        in
        {
          a = "add";
          b = "branch";
          br = "branch -r";
          c = "commit";
          co = "checkout";
          df = "diff --no-ext-diff --ignore-space-change --ignore-blank-lines";
          f = "fetch --verbose";
          fa = "fetch --all --verbose";
          l = "!tig";
          la = "!tig --all";
          s = "status --short --branch";

          au = "!f() { git ls-files --unmerged | cut -f2 | sort -u ; }; git add `f`";
          eu = "!f() { git ls-files --unmerged | cut -f2 | sort -u ; }; nvim -p `f`";
        };

      # Appearance
      color = {
        diff-highlight = {
          oldnormal = "1 0";
          oldhighlight = "210 52";
          newnormal = "2 0";
          newhighlight = "120 22";
        };
        diff = {
          oldMoved = "251 0";
          newMoved = "251 0";
        };
      };

      column = {
        ui = "never";
      };

      diff = {
        algorithm = "histogram";
        colorMoved = "zebra";
        context = 5;
        indentHeuristic = true;
        mnemonicPrefix = true;
      };

      # DX
      branch = {
        autoSetupRebase = "always";
        sort = "-committerdate";
      };

      fetch = {
        prune = true;
        pruneTags = true;
      };

      init = {
        defaultBranch = "main";
      };

      merge = {
        conflictStyle = lib.mkDefault "zdiff3";
      };

      pull = {
        rebase = true;
      };

      push = {
        default = "simple";
        autoSetupRemote = true;
        followTags = true;
        gpgSign = "if-asked";
      };

      rerere = {
        enabled = true;
        autoupdate = true;
      };

      rebase = {
        autoSquash = true;
        autoStash = true;
      };

      stash = {
        showPatch = true;
      };

      tag = {
        sort = "version:refname";
      };
    };
  };

  programs.mergiraf = {
    enable = true;
  };
}
