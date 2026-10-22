{
  lib,
  buildNpmPackage,
  fetchFromGitHub,
  nodejs_26,
}:

buildNpmPackage {
  pname = "bend2-lsp";
  version = "0.2.0-unstable-2026-10-22";

  src = fetchFromGitHub {
    owner = "don2e4";
    repo = "bend2-lsp";
    rev = "ed06027cc5396050459776accf91214f0c433f79";
    hash = "sha256-6gYjqWC7hQWXj9BA3MIu0WejNjzyvuNYFvF8pEVvfrs=";
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
