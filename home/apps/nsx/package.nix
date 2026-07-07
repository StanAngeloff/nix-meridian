{
  writeShellApplication,
  name ? "nsx",
}:
writeShellApplication {
  inherit name;

  text = builtins.replaceStrings [ "@name@" ] [ name ] (builtins.readFile ./nsx.sh);
}
