{
  writeShellApplication,
  execPath,
  name ? "x-www-browser",
}:
writeShellApplication {
  inherit name;

  text = ''
    exec "${execPath}" "$@"
  '';
}
