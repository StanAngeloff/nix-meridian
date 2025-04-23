{
  writeShellApplication,
  package,
  execPath,
  name ? "x-www-browser",
}:
writeShellApplication {
  inherit name;

  text = ''
    exec "${package}/bin/${execPath}" "$@"
  '';
}
