{ lib, craneLib, makeWrapper, pkg-config, sqlite, coreutils, geoclue2-with-demo-agent, owly }:

let
  # `.owly` is the flake's owly input, so flake.lock is owly's only pin.
  common = {
    src = craneLib.cleanCargoSource ./.;
    strictDeps = true;
    nativeBuildInputs = [ pkg-config ];
    buildInputs = [ sqlite ];
    postUnpack = /* bash */ ''
      ln --symbolic ${owly} $sourceRoot/.owly
    '';
  };
in
craneLib.buildPackage (common // {
  cargoArtifacts = craneLib.buildDepsOnly common;

  nativeBuildInputs = common.nativeBuildInputs ++ [ makeWrapper ];

  postUnpack = common.postUnpack + /* bash */ ''
    cp --recursive ${../styling} $sourceRoot/../styling
  '';

  postInstall = /* bash */ ''
    # Versioned theming data travels in the closure so a running desktop never
    # reads the working tree. `--set-default` leaves DESKTOPCTL_DATA free for
    # authoring against a checkout. Wallpapers are deliberately absent: they
    # are gitignored user assets and resolve through DESKTOPCTL_REPO.
    mkdir --parents "$out/share/desktopctl/styling"
    # Writable: crane rewrites every installed file to drop toolchain references.
    cp --recursive --no-preserve=mode \
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
})
