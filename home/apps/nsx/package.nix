{
  writeShellApplication,
  name ? "nsx",
  replaceVars,
}:
writeShellApplication {
  inherit name;

  text = builtins.readFile (
    replaceVars ./nsx.sh {
      inherit name;
    }
  );
}
