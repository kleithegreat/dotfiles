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
    # Theming data travels in the closure (docs/desktopctl.md); wallpapers resolve through DESKTOPCTL_REPO.
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

  meta = {
    description = "Unified desktop daemon and CLI for the dotfiles desktop stack";
    mainProgram = "desktopctl";
    platforms = lib.platforms.linux;
  };
})
