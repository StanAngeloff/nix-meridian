{
  lib,
  runCommand,
  writeTextDir,
  dconf,
  dconfKeyfile,
  ...
}:
{
  # Compiled the way nixpkgs' programs.dconf compiles its databases.
  substitutions.dconfDatabase = "${runCommand "claude-bubble-dconf" {
    nativeBuildInputs = [ (lib.getBin dconf) ];
  } "dconf compile $out ${writeTextDir "settings" dconfKeyfile}"}";
}
