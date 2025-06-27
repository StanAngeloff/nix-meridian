{
  writeShellApplication,
  name ? "nsx",
  replaceVars,
}:
writeShellApplication {
  inherit name;

  text = builtins.toString (
    replaceVars ./nsx.sh {
      inherit name;
    }
  );
}
