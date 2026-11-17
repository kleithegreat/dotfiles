{
  lib,
  buildNpmPackage,
  fetchFromGitHub,
  nodejs_26,
}:

buildNpmPackage {
  pname = "bend2-lsp";
  version = "0.2.0-unstable-2026-11-15";

  src = fetchFromGitHub {
    owner = "don2e4";
    repo = "bend2-lsp";
    rev = "382936b01d92576d8c9a64626b5118d7b6643e25";
    hash = "sha256-G/+j4l8krzar4hN2Hs7i94ylChQyj0alb7zg5uojwwc=";
  };

  npmDepsHash = "sha256-dzm7k/L8rCJyZFZcoGV4aMjSzZcGJ22D2j4azit/ybM=";
  nodejs = nodejs_26;

  meta = {
    description = "Language server for Bend 2";
    homepage = "https://github.com/don2e4/bend2-lsp";
    license = lib.licenses.asl20;
    mainProgram = "bend2-lsp";
  };
}
