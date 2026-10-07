{ ... }:
{
  # On by default; --without-gpu revokes. hooks.sh branches on the grant.
  grants = [
    {
      name = "gpu";
      default = true;
      description = "expose the GPU render nodes so windows started in the bubble draw with hardware acceleration (the kernel GPU driver becomes reachable from inside)";
    }
  ];
}
