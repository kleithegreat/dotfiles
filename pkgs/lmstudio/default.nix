{ lib, appimageTools, fetchurl, graphicsmagick, runtimeShell, stdenv, upstreamLmstudio }:

let
  pname = "lmstudio";
  version = "0.4.21-2";
  src = fetchurl {
    url = "https://installers.lmstudio.ai/linux/x64/${version}/LM-Studio-${version}-x64.AppImage";
    hash = "sha256-EBQ3bYnWaMOBTNIOKxRqB2FGdg3tHvB7lo+2HFje01U=";
  };
  appimageContents = appimageTools.extract {
    inherit pname version src;
  };
in
appimageTools.wrapType2 {
  inherit pname version src;

  nativeBuildInputs = [ graphicsmagick ];

  extraPkgs = pkgs: [ pkgs.ocl-icd ];

  # The desktop file must point at an absolute shell-parent launcher, not the
  # AppImage/FHS wrapper, or Vicinae's detached launch loses the app.
  extraInstallCommands = ''
    mkdir -p $out/share/applications

    src_icon="${appimageContents}/usr/share/icons/hicolor/0x0/apps/lm-studio.png"
    sizes=("16x16" "32x32" "48x48" "64x64" "128x128" "256x256")
    for size in "''${sizes[@]}"; do
      install -dm755 "$out/share/icons/hicolor/$size/apps"
      gm convert "$src_icon" -resize "$size" "$out/share/icons/hicolor/$size/apps/lm-studio.png"
    done

    install -m 444 -D ${appimageContents}/lm-studio.desktop -t $out/share/applications

    mv $out/bin/lmstudio $out/bin/lm-studio

    install -m 755 -D /dev/stdin $out/bin/lm-studio-desktop <<EOF
    #!${runtimeShell}
    "$out/bin/lm-studio" "\$@"
    EOF

    substituteInPlace $out/share/applications/lm-studio.desktop \
      --replace-fail 'Exec=AppRun --no-sandbox %U' "Exec=$out/bin/lm-studio-desktop %U"

    install -m 755 ${appimageContents}/resources/app/.webpack/lms $out/bin/
    patchelf --set-interpreter "${stdenv.cc.bintools.dynamicLinker}" $out/bin/lms
  '';

  meta = upstreamLmstudio.meta // {
    mainProgram = "lm-studio";
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
  };
}
