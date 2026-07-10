{ ... }:
{
  grants = [
    {
      name = "nix";
      description = "bind the Nix daemon socket for this session (enables nix build, but also nix-env and nix store gc against the host)";
    }
  ];
}
