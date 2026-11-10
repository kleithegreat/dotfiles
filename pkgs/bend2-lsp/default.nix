{
  lib,
  buildNpmPackage,
  fetchFromGitHub,
  nodejs_26,
}:

buildNpmPackage {
  pname = "bend2-lsp";
  version = "0.2.0-unstable-2026-11-09";

  src = fetchFromGitHub {
    owner = "don2e4";
    repo = "bend2-lsp";
    rev = "b79e6a5f7c36011205f8a90decc5e64139dfffce";
    hash = "sha256-Yd1H2auLZ1ocunB9m66yqWZsGwIoo6M5CHjEk+Z71IA=";
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
