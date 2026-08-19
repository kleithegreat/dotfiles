{ lib, rustPlatform, makeWrapper, coreutils, geoclue2-with-demo-agent, power-profiles-daemon }:

rustPlatform.buildRustPackage {
  pname = "desktopctl";
  version = "0.1.0";

  src = ./.;
  cargoLock.lockFile = ./Cargo.lock;

  nativeBuildInputs = [ makeWrapper ];

  postUnpack = ''
    cp -r ${../styling} $sourceRoot/../styling
  '';

  postInstall = ''
    wrapProgram "$out/bin/desktopctl" \
      --prefix PATH : ${lib.makeBinPath [ coreutils ]} \
      --prefix PATH : ${geoclue2-with-demo-agent}/libexec/geoclue-2.0/demos

    # pkexec resets PATH, and the laptop host invokes this one through it.
    wrapProgram "$out/bin/laptop-power-profile" \
      --prefix PATH : ${lib.makeBinPath [ power-profiles-daemon ]}
  '';

  meta = with lib; {
    description = "Unified desktop daemon and CLI for the dotfiles desktop stack";
    mainProgram = "desktopctl";
    platforms = platforms.linux;
  };
}
