{
  # Old Windows solid-state drive (KIOXIA 512 GB) repurposed as encrypted bulk storage at /annex.
  #
  # The disk is its own LUKS2 container (no LVM): one partition, encrypted with the same passphrase as root (key slot 0)
  # plus a keyfile (key slot 1). The keyfile is created by hand during provisioning and lives on the already-encrypted root filesystem.
  # It is deliberately never placed in the Nix store or on the unencrypted /boot partition,
  # because the store is world readable and that would defeat the encryption.
  #
  # Unlocking happens in stage 2, after the root filesystem is already open, so booting still asks for a single passphrase.
  # "discard" passes the TRIM hint through to the solid-state drive;
  # "nofail" ensures a missing or failed disk never blocks boot.
  environment.etc.crypttab = {
    mode = "0600";
    text = ''
      annex  UUID=0c62c970-b356-4e98-8add-a06d49ae623f  /etc/keys/annex.key  luks,discard,nofail
    '';
  };

  fileSystems."/annex" = {
    device = "/dev/mapper/annex";
    fsType = "ext4";
    options = [ "nofail" ];
  };
}
