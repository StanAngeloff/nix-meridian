{ systemd, ... }:
{
  # systemd-run and systemctl, to run the session in a transient user scope and stop it at cleanup.
  runtimeInputs = [ systemd ];
}
