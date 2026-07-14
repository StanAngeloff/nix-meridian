{ wl-clipboard, ... }:
{
  runtimeInputs = [ wl-clipboard ];

  # On by default; --without-clipboard revokes. hooks.sh branches on the grant.
  grants = [
    {
      name = "clipboard";
      default = true;
      description = "expose the Wayland compositor socket for wl-copy/wl-paste clipboard integration";
    }
  ];
}
