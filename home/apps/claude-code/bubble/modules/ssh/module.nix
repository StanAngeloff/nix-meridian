{
  openssh,
  ...
}:
{
  # ssh-add, for the before-run check that warns about IdentityFile keys missing from the agent.
  runtimeInputs = [ openssh ];
}
