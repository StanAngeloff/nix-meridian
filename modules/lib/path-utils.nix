{ lib, ... }:
rec {
  # Generate all parent paths for a given path.
  _generateParentPaths =
    path:
    let
      # Remove leading and trailing slashes, then split
      parts = lib.filter (s: s != "") (lib.splitString "/" path);

      # Create paths of increasing length
      makePaths =
        n:
        if n == 0 then
          [ ]
        else
          let
            subPath = "/" + (lib.concatStringsSep "/" (lib.take n parts)) + "/";
          in
          [ subPath ] ++ (makePaths (n - 1));
    in
    lib.reverseList (makePaths (lib.length parts));

  # Collect all unique parent paths from the list of paths.
  collectPaths = paths: lib.unique (lib.concatMap _generateParentPaths paths);
}
