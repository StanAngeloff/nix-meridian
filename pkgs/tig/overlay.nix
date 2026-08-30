{ tig }:
tig.overrideAttrs (prev: {
  patches = (prev.patches or [ ]) ++ [
    ./patches/move-next-diff.patch
    ./patches/diff-line-fill.patch
    ./patches/echo-status-survives.patch
    ./patches/annotation-marks.patch
  ];
})
