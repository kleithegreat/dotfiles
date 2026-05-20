{ lib, rustPlatform, makeWrapper, coreutils, geoclue2-with-demo-agent }:

rustPlatform.buildRustPackage {
  pname = "desktopctl";
  version = "0.1.0";

  src = ./.;
  cargoLock.lockFile = ./Cargo.lock;

  nativeBuildInputs = [ makeWrapper ];

  postUnpack = ''
    cp -r ${../themes} $sourceRoot/../themes
  '';

  postInstall = ''
    wrapProgram "$out/bin/desktopctl" \
      --prefix PATH : ${lib.makeBinPath [ coreutils ]} \
      --prefix PATH : ${geoclue2-with-demo-agent}/libexec/geoclue-2.0/demos
  '';

  meta = with lib; {
    description = "Unified desktop daemon and CLI for the dotfiles desktop stack";
    mainProgram = "desktopctl";
    platforms = platforms.linux;
  };
}
