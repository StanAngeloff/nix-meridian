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
    rev = "5836300d66adb31a16aa8d922a272a07bc3060e2";
    hash = "sha256-luEh3y0UfiAtS8FKtxCs3kmKWV/lkUmtl05+vDNGWFY=";
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
