{
  programs.git = {
    enable = true;
    lfs.enable = true;
    diff-so-fancy.enable = true;

    userName = "Stan Angeloff";
    userEmail = "stanimir@angeloff.name";

    signing = {
      key = "595EA753";
      signByDefault = true;
    };

    aliases =
      let
        gitLogFormat = "%C(red)%h%C(reset) -%C(yellow)%d%C(reset) %s %C(green)%cr (%cd) %C(blue)%an%C(reset) ▸ %C(cyan)%cn%C(reset)";
      in
      {
        a = "add";
        b = "branch";
        br = "branch -r";
        c = "commit";
        co = "checkout";
        df = "diff --no-ext-diff --ignore-space-change --ignore-blank-lines --color-moved-ws=ignore-space-change";
        f = "fetch --verbose";
        fa = "fetch --all --verbose";
        l = "log --graph --date=human --pretty=format:'${gitLogFormat}'";
        la = "log --all --tags --graph --date=human --pretty=format:'${gitLogFormat}'";
        s = "status --short --branch";

        au = "!f() { git ls-files --unmerged | cut -f2 | sort -u ; }; git add `f`";
        eu = "!f() { git ls-files --unmerged | cut -f2 | sort -u ; }; nvim -p `f`";

        ig = "!git ls-files -v | grep \"^[[:lower:]]\"";

        ro = "!sh -c 'git rebase --interactive origin/\"$( git symbolic-ref --short HEAD )\"'";
      };

    # Git configuration https://git-scm.com/docs/git-config
    extraConfig = {
      github = {
        user = "StanAngeloff";
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
        conflictstyle = "zdiff3";
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
}
