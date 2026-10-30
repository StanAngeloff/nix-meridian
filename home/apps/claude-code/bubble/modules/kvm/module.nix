{ ... }:
{
  # Accepted as the --with-kvm launcher flag; hooks.sh branches on the grant.
  grants = [
    {
      name = "kvm";
      description = "expose /dev/kvm so virtual machines started in the bubble run with hardware acceleration (the kernel KVM driver becomes reachable from inside)";
    }
  ];
}
