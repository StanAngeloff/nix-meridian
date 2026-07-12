{ ... }:
{
  grants = [
    {
      name = "pnpm";
      description = "point pnpm at a project-local store (<project>/node_modules/.pnpm-store) so installs work inside the bubble; auto-on when ./package.json exists";
    }
  ];
}
