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

    aliases = {
      a = "add";
      b = "branch";
      br = "branch -r";
      c = "commit";
      co = "checkout";
      df = "diff -U5 --minimal --histogram --indent-heuristic --ignore-space-change --ignore-blank-lines --no-ext-diff --color-moved=zebra --color-moved-ws=ignore-space-change";
      dfa = "diff -U5 --minimal --histogram --indent-heuristic --ignore-all-space    --ignore-blank-lines --no-ext-diff --color-moved=zebra --color-moved-ws=ignore-all-space    --color-words='[^ \\t\\n;,]+'";
      f = "fetch       --prune --verbose";
      fa = "fetch --all --prune --verbose";
      l = "log       --graph        --abbrev-commit --date=human --pretty=format:'%C(red)%h%C(reset) -%C(yellow)%d%C(reset) %s %C(green)%cr (%cd) %C(blue)%an%C(reset) ▸ %C(cyan)%cn%C(reset)'";
      la = "log --all --graph --tags --abbrev-commit --date=human --pretty=format:'%C(red)%h%C(reset) -%C(yellow)%d%C(reset) %s %C(green)%cr (%cd) %C(blue)%an%C(reset) ▸ %C(cyan)%cn%C(reset)'";
      s = "status -sb";
      su = "submodule update --init --recursive";

      au = "!f() { git ls-files --unmerged | cut -f2 | sort -u ; }; git add `f`";
      eu = "!f() { git ls-files --unmerged | cut -f2 | sort -u ; }; vim -p `f`";

      ig = "!git ls-files -v | grep \"^[[:lower:]]\"";

      ro = "!sh -c 'git rebase -i --autostash --autosquash origin/\"$( git symbolic-ref --short HEAD )\"'";
    };

    # Git configuration https://git-scm.com/docs/git-config
    extraConfig = {
      github = {
        user = "StanAngeloff";
      };

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

      diff = {
        colorMoved = "default";
      };

      branch = {
        autoSetupRebase = "always";
      };

      push = {
        default = "upstream";
        gpgSign = "if-asked";
      };

      rerere = {
        enabled = true;
      };

      rebase = {
        autoSquash = true;
        autoStash = true;
      };

      stash = {
        showPatch = true;
      };
    };
  };
}
