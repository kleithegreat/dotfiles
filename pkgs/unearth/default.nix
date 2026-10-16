{
  lib,
  fetchurl,
  llama-cpp,
  makeWrapper,
  poppler-utils,
  rustPlatform,
}:

let
  model = fetchurl {
    url = "https://huggingface.co/ggml-org/embeddinggemma-2-GGUF/resolve/bfcd298762cc34d0357ece5ebdd31791a3a374d8/embeddinggemma-2-Q8_0.gguf";
    hash = "sha256-IYisHeykt33/79YDwndqnXbZ107AGEE5KYLruECwkTU=";
  };
in
rustPlatform.buildRustPackage {
  pname = "unearth";
  version = "0.1.0";

  src = lib.fileset.toSource {
    root = ./.;
    fileset = lib.fileset.unions [
      ./Cargo.toml
      ./Cargo.lock
      ./src
    ];
  };
  cargoLock.lockFile = ./Cargo.lock;

  nativeBuildInputs = [ makeWrapper ];

  postInstall = /* bash */ ''
    wrapProgram "$out/bin/unearth" \
      --set UNEARTH_MODEL ${model} \
      --prefix PATH : ${
        lib.makeBinPath [
          llama-cpp
          poppler-utils
        ]
      }
  '';

  meta = {
    description = "Local semantic search over documents with EmbeddingGemma 2";
    mainProgram = "unearth";
    platforms = lib.platforms.linux;
  };
}
