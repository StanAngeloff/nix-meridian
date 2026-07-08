# Point Tesseract at the "best" float LSTM models from tesseract-ocr/tessdata_best instead of nixpkgs' default integer-quantized models from tesseract-ocr/tessdata.
# The best models are the most accurate and are the ones upstream recommends for training/fine-tuning;
# the trade-off is larger files, slightly slower recognition, and LSTM engine only (no legacy --oem 0, which OCR and ocrmypdf do not use).
#
# Mechanism: wrapper.nix accepts a `tessdata` argument documented as "a list of files or a directory containing files".
# Passing it explicitly bypasses the default, which would otherwise fetch every model in the standard repository (languages.all).
# We fetch only the languages we need, mirroring nixpkgs' own languageFile helper in pkgs/applications/graphics/tesseract/languages.nix.
#
# Apply the result to tesseract5, the concrete derivation, rather than the tesseract alias:
# consumers such as ocrmypdf request pkgs.tesseract5 by name (nixpkgs pkgs/top-level/python-packages.nix),
# so overriding only the alias would leave them on the standard models.
{
  lib,
  tesseract,
  fetchurl,
}:
let
  # Pinned to the 4.1.0 tag, the same release nixpkgs pins for the standard repository.
  rev = "4.1.0";

  # - eng is required by the wrapper's sanity check;
  # - bul covers Cyrillic documents;
  # - osd provides orientation and script detection (used by ocrmypdf --rotate-pages).
  #
  # Regenerate a hash with:
  # $ nix store prefetch-file --json https://github.com/tesseract-ocr/tessdata_best/raw/<rev>/<lang>.traineddata
  hashes = {
    eng = "sha256-goCu0Hgv4nJXpo6hD+fvMkyg+Nhb0v0UXRwrVgvLZro=";
    bul = "sha256-hzIvB64CPQ9h08ElB/bx7SJBHADxsuci0uE7cjWE+tE=";
    osd = "sha256-nPXVdvzEdWTxEmWEHlyoOQAefm84/396rPRtFalrAP8=";
  };

  traineddata =
    lang: hash:
    fetchurl {
      url = "https://github.com/tesseract-ocr/tessdata_best/raw/${rev}/${lang}.traineddata";
      inherit hash;
    };
in
tesseract.override {
  tessdata = lib.mapAttrsToList traineddata hashes;
}
