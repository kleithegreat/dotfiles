{ lib, appimageTools, fetchurl, runtimeShell, stdenv, upstreamLmstudio }:

let
  pname = "lmstudio";
  version = "0.4.25-1";
  src = fetchurl {
    url = "https://installers.lmstudio.ai/linux/x64/${version}/LM-Studio-${version}-x64.AppImage";
    hash = "sha256-7KRnRGyDOCRpfovvqzAP5Saf35hOPuQ4X8uthQLwfFM=";
  };
  appimageContents = appimageTools.extract {
    inherit pname version src;
  };
in
appimageTools.wrapType2 {
  inherit pname version src;

  extraPkgs = pkgs: [ pkgs.ocl-icd ];

  # The desktop file must point at an absolute shell-parent launcher, not the
  # AppImage/FHS wrapper, or Vicinae's detached launch loses the app.
  # Upstream names the entry after its appId; keep the desktop ID stable as
  # lm-studio.desktop so launcher state survives the rename.
  extraInstallCommands = ''
    install -m 444 -D ${appimageContents}/ai.elementlabs.lmstudio.desktop \
      $out/share/applications/lm-studio.desktop

    cp --recursive ${appimageContents}/usr/share/icons $out/share/

    mv $out/bin/lmstudio $out/bin/lm-studio

    install -m 755 -D /dev/stdin $out/bin/lm-studio-desktop <<EOF
    #!${runtimeShell}
    "$out/bin/lm-studio" "\$@"
    EOF

    substituteInPlace $out/share/applications/lm-studio.desktop \
      --replace-fail 'Exec=AppRun %U' "Exec=$out/bin/lm-studio-desktop %U"

    install -m 755 ${appimageContents}/resources/app/.webpack/lms $out/bin/
    patchelf --set-interpreter "${stdenv.cc.bintools.dynamicLinker}" $out/bin/lms
  '';

  meta = upstreamLmstudio.meta // {
    mainProgram = "lm-studio";
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
  };
}
