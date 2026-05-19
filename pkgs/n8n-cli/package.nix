{
  lib,
  buildGoModule,
  fetchFromGitHub,
}:
buildGoModule rec {
  pname = "n8n-cli";
  version = "0.7.1";

  src = fetchFromGitHub {
    owner = "edenreich";
    repo = "n8n-cli";
    tag = "v${version}";
    hash = "sha256-gcZDahq8iceg5+9SdRwrUZedtX6zV+/sA2zvoWypDnI=";
  };

  vendorHash = "sha256-fKElh5sQ+i/PS28CNfdPtimLr+CMJshYHkrPB0Aa0SA=";

  ldflags = [
    "-s"
    "-w"
    "-X github.com/edenreich/n8n-cli/config.Version=${version}"
    "-X github.com/edenreich/n8n-cli/config.Commit=v${version}"
  ];

  postInstall = ''
    mv $out/bin/n8n-cli $out/bin/n8n
  '';

  meta = with lib; {
    description = "CLI tool for managing n8n workflows";
    homepage = "https://github.com/edenreich/n8n-cli";
    license = licenses.mit;
    mainProgram = "n8n";
  };
}
