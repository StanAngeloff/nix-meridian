{
  programs.git = {
    enable = true;
    lfs.enable = true;

    userName = "Stan Angeloff";
    userEmail = "stanimir@angeloff.name";

    aliases = {
      a   = "add";
      b   = "branch";
      br  = "branch -r";
      c   = "commit";
      co  = "checkout";
      df  = "diff -U5 --minimal --histogram --indent-heuristic --ignore-space-change --ignore-blank-lines --no-ext-diff --color-moved=zebra --color-moved-ws=ignore-space-change";
      dfa = "diff -U5 --minimal --histogram --indent-heuristic --ignore-all-space    --ignore-blank-lines --no-ext-diff --color-moved=zebra --color-moved-ws=ignore-all-space    --color-words='[^ \\t\\n;,]+'";
      f   = "fetch       --prune --verbose";
      fa  = "fetch --all --prune --verbose";
      l   = "log       --graph        --abbrev-commit --date=human --pretty=format:'%C(red)%h%C(reset) -%C(yellow)%d%C(reset) %s %C(green)%cr (%cd) %C(blue)%an%C(reset) ▸ %C(cyan)%cn%C(reset)'";
      la  = "log --all --graph --tags --abbrev-commit --date=human --pretty=format:'%C(red)%h%C(reset) -%C(yellow)%d%C(reset) %s %C(green)%cr (%cd) %C(blue)%an%C(reset) ▸ %C(cyan)%cn%C(reset)'";
      s   = "status -sb";
      su  = "submodule update --init --recursive";

      au = "!f() { git ls-files --unmerged | cut -f2 | sort -u ; }; git add `f`";
      eu = "!f() { git ls-files --unmerged | cut -f2 | sort -u ; }; vim -p `f`";

      ig = "!git ls-files -v | grep \"^[[:lower:]]\"";

      ro = "!sh -c 'git rebase -i --autostash --autosquash origin/\"$( git symbolic-ref --short HEAD )\"'";
    };
  };
}
