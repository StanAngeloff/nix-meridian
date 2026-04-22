{ pkgs, pkgs-unstable, ... }:
let
  voxize = pkgs.callPackage ./package.nix {
    # NOTE: nixpkgs-25.11 ships python313Packages.openai 2.7.2, but voxize monkey-patches openai._streaming.Stream.__stream__
    # against the 2.10+ API that introduced Stream._options. 2.7.2 has no such attribute, so the patch raised AttributeError
    # on the first SSE event. Pull openai (and the whole Python interpreter) from nixpkgs-unstable so the patch site
    # resolves and to avoid a ~200-commit SDK drift biting us elsewhere.
    #
    # We pass pkgs-unstable.python313 wholesale rather than overriding just openai via packageOverrides: that approach
    # produces a new python313 derivation with a different store hash from the python313 that pkgs-unstable's openai
    # was built against and buildPythonApplication refuses to mix two "3.13.12" interpreters with different store paths.
    # Using pkgs-unstable.python313 directly keeps the interpreter and every propagatedBuildInput consistent.
    #
    # package.nix can't pull this itself - callPackage only auto-injects top-level pkgs and the python interpreter
    # switch has to happen at the call site.
    python313 = pkgs-unstable.python313;
  };
in
{
  home.packages = [
    voxize
  ];
}
