{ gnupg, ... }:
{
  # prepare.sh seeds the synthetic public keyring host-side with the real gpg.
  runtimeInputs = [ gnupg ];
}
