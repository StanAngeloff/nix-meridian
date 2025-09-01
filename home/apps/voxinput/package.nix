{
  voxinput,
  fetchFromGitHub,
}:
voxinput.overrideAttrs (previousAttrs: rec {
  version = "0.6.2";

  src = fetchFromGitHub {
    owner = "richiejp";
    repo = "VoxInput";
    rev = "v${version}";
    hash = "sha256-+W+xaPYwofYdsV8C2G7hOugUekrdmA6Q0o4xUvbbLlg=";
  };

  vendorHash = "sha256-HOXjD4mwvK3jcFmpZyvKB7WOfpCIDlUWJTJSTN7wFXM=";

  patches = [
    ./patches/0001-feat-add-support-for-injecting-a-prompt-via-env-vari.patch
    ./patches/0002-feat-replace-dotool-with-wl-copy.patch
  ];

  postInstall =
    let
      marker = "--prefix PATH";
    in
    builtins.replaceStrings
      [ marker ]
      [
        (builtins.concatStringsSep " " [
          "--set-default OPENAI_BASE_URL \"https://api.openai.com/v1\""
          "--set-default OPENAI_WS_BASE_URL \"wss://api.openai.com/v1/realtime\""
          "--run \"export OPENAI_API_KEY=\\\${OPENAI_API_KEY-\\$(secret-tool lookup service openai key api 2>/dev/null)}\""
          marker
        ])
      ]
      (previousAttrs.postInstall or "");

  meta.mainProgram = "voxinput";
})
