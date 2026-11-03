{ lib, rustPlatform, makeWrapper, coreutils, geoclue2-with-demo-agent, owly }:

rustPlatform.buildRustPackage {
  pname = "desktopctl";
  version = "0.1.0";

  src = ./.;
  cargoLock.lockFile = ./Cargo.lock;

  nativeBuildInputs = [ makeWrapper ];

  # `.owly` is the flake's owly input, so flake.lock is owly's only pin.
  postUnpack = /* bash */ ''
    cp --recursive ${../styling} $sourceRoot/../styling
    ln --symbolic ${owly} $sourceRoot/.owly
  '';

  postInstall = /* bash */ ''
    # Versioned theming data travels in the closure so a running desktop never
    # reads the working tree. `--set-default` leaves DESKTOPCTL_DATA free for
    # authoring against a checkout. Wallpapers are deliberately absent: they
    # are gitignored user assets and resolve through DESKTOPCTL_REPO.
    mkdir --parents "$out/share/desktopctl/styling"
    cp --recursive \
      ../styling/colors ../styling/bases ../styling/state.json \
      "$out/share/desktopctl/styling/"

    wrapProgram "$out/bin/desktopctl" \
      --set-default DESKTOPCTL_DATA "$out/share/desktopctl/styling" \
      --prefix PATH : ${lib.makeBinPath [ coreutils ]} \
      --prefix PATH : ${geoclue2-with-demo-agent}/libexec/geoclue-2.0/demos
  '';

  meta = with lib; {
    description = "Unified desktop daemon and CLI for the dotfiles desktop stack";
    mainProgram = "desktopctl";
    platforms = platforms.linux;
  };
}
