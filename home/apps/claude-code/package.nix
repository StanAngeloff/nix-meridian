{
  writeShellApplication,
  replaceVars,
  nodejs_24,
  bubblewrap,
  socat,
}:
let
  package = "@anthropic-ai/claude-code";
  version = "latest";
in
writeShellApplication {
  name = "claude-code-npx";
  runtimeInputs = [
    nodejs_24
    bubblewrap
    socat
  ];
  runtimeEnv = import ./env.nix;
  text = builtins.readFile (
    replaceVars ./claude-code-npx.sh {
      inherit package version;
    }
  );
}
