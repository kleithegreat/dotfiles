{ lib, appimageTools, fetchurl, runtimeShell, stdenv, upstreamLmstudio }:

let
  pname = "lmstudio";
  version = "0.4.26-4";
  src = fetchurl {
    url = "https://installers.lmstudio.ai/linux/x64/${version}/LM-Studio-${version}-x64.AppImage";
    hash = "sha256-LGKjipOtA8pdqu8ogEiAvhZ1Zng/+vwXPOLhyxC3VS4=";
  };
  appimageContents = appimageTools.extract {
    inherit pname version src;
  };
in
appimageTools.wrapType2 {
  inherit pname version src;

  extraPkgs = pkgs: [ pkgs.ocl-icd ];

  # Shell-parent launcher (docs/nix.md); the desktop ID stays lm-studio so
  # launcher state survives upstream's rename to its appId.
  extraInstallCommands = /* bash */ ''
    install -D --mode=444 ${appimageContents}/ai.elementlabs.lmstudio.desktop \
      $out/share/applications/lm-studio.desktop

    cp --recursive ${appimageContents}/usr/share/icons $out/share/

    mv $out/bin/lmstudio $out/bin/lm-studio

    install -D --mode=755 /dev/stdin $out/bin/lm-studio-desktop <<EOF
    #!${runtimeShell}
    "$out/bin/lm-studio" "\$@"
    EOF

    substituteInPlace $out/share/applications/lm-studio.desktop \
      --replace-fail 'Exec=AppRun %U' "Exec=$out/bin/lm-studio-desktop %U"

    install --mode=755 ${appimageContents}/resources/app/.webpack/lms $out/bin/
    patchelf --set-interpreter "${stdenv.cc.bintools.dynamicLinker}" $out/bin/lms
  '';

  meta = upstreamLmstudio.meta // {
    mainProgram = "lm-studio";
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
  };
}
