{ pkgs, ... }:
{
  services.pcscd.enable = true;

  # Smart-card reader USB nodes carry ID_SMARTCARD_READER=1, so systemd's 70-uaccess.rules tags them `uaccess`,
  # and logind lays a per-user POSIX ACL that leaves the owning group (`pcscd`) with no access (`group::---`),
  # silently defeating the GROUP="pcscd" grant from the stock 92_pcscd_ccid.rules. The unprivileged pcscd daemon
  # is then denied (LIBUSB_ERROR_ACCESS) the moment it must re-open a reader after a USB re-enumeration
  # (suspend / hibernate / replug), and the reader vanishes until the node's permissions are rebuilt.
  # Since logind's uaccess only ever manages the active-user ACL entry, a *named group* ACL entry for pcscd
  # survives it — so re-applying it on every reader hotplug keeps the daemon's access intact across re-enumerations.
  services.udev.extraRules = ''
    ACTION=="add|change", SUBSYSTEM=="usb", ENV{ID_SMARTCARD_READER}=="1", RUN+="${pkgs.acl}/bin/setfacl -m g:pcscd:rw- $env{DEVNAME}"
  '';

  # Register OpenSC with p11-kit so browsers can discover the token via the proxy.
  # onepin variant avoids double-PIN prompts on single-PIN cards like the InfoNotary card.
  environment.etc."pkcs11/modules/opensc-pkcs11".text =
    "module: ${pkgs.opensc}/lib/onepin-opensc-pkcs11.so\n";

  environment.systemPackages = with pkgs; [
    opensc
    p11-kit
    pcsc-tools
    nssTools
  ];
}
