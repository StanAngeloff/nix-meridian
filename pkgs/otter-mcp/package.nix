{
  python313,
  fetchFromGitHub,
  fetchPypi,
}:
let
  python = python313;

  mcp = python.pkgs.mcp.overridePythonAttrs (prev: rec {
    version = "1.27.1";
    src = fetchPypi {
      pname = "mcp";
      inherit version;
      hash = "sha256-D0fhgg+Pj5QUZrOXSesdGDmgTK3corxg6dRuipmRSSQ=";
    };
    dependencies = (prev.dependencies or [ ]) ++ [
      python.pkgs.typing-extensions
      python.pkgs.typing-inspection
    ];
  });
in
python.pkgs.buildPythonApplication {
  pname = "otter-mcp";
  version = "0.1.0";

  src = fetchFromGitHub {
    owner = "StanAngeloff";
    repo = "otter-mcp";
    rev = "09d96353ecdaf63c35732b53d1fc5b5e773cec54";
    hash = "sha256-434PdnAJAQ2m4a9iA/0ftANXEDjHeNrK0J2cyaGvqMQ=";
  };

  pyproject = true;

  build-system = [ python.pkgs.hatchling ];

  dependencies = [
    mcp
    python.pkgs.pyotp
  ];

  pythonImportsCheck = [ "otter_mcp" ];

  meta = {
    description = "Unofficial Otter.ai MCP server";
    homepage = "https://github.com/StanAngeloff/otter-mcp";
    mainProgram = "otter-mcp";
  };
}
