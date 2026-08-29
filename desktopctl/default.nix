{ lib, rustPlatform, makeWrapper, coreutils, geoclue2-with-demo-agent, power-profiles-daemon }:

rustPlatform.buildRustPackage {
  pname = "desktopctl";
  version = "0.1.0";

  src = ./.;
  cargoLock.lockFile = ./Cargo.lock;

  nativeBuildInputs = [ makeWrapper ];

  postUnpack = ''
    cp --recursive ${../styling} $sourceRoot/../styling
  '';

  postInstall = ''
    # Versioned theming data travels in the closure so a running desktop never
    # reads the working tree. `--set-default` leaves DESKTOPCTL_DATA free for
    # authoring against a checkout. Wallpapers are deliberately absent: they
    # are gitignored user assets and resolve through DESKTOPCTL_REPO.
    mkdir --parents "$out/share/desktopctl/styling"
    cp --recursive \
      ../styling/colors ../styling/presets ../styling/bases ../styling/state.json \
      "$out/share/desktopctl/styling/"

    wrapProgram "$out/bin/desktopctl" \
      --set-default DESKTOPCTL_DATA "$out/share/desktopctl/styling" \
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
