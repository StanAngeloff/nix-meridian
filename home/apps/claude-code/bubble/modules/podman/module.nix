{ ... }:
{
  # Accepted as the --with-podman launcher flag; hooks.sh branches on the grant.
  grants = [
    {
      name = "podman";
      description = "expose the rootless podman API socket for this session (sets CONTAINER_HOST and DOCKER_HOST; host-side podman will mount anything the user can read)";
    }
  ];
}
