{
  lib,
  appimageTools,
  fetchurl,
  makeWrapper,
}:

let
  pname = "t3-code";
  version = "0.0.0-alpha.22";

  src = fetchurl {
    url = "https://github.com/pingdotgg/t3code/releases/download/v${version}/T3-Code-${version}-x86_64.AppImage";
    hash = "sha256-h0x2ilTjQdQfglqWPKnDOUQq/smr1jByp3ddtPPZmaY=";
  };

  appimageContents = appimageTools.extract { inherit pname version src; };
in
appimageTools.wrapType2 {
  inherit pname version src;

  nativeBuildInputs = [ makeWrapper ];

  extraInstallCommands = ''
    install -Dm 444 ${appimageContents}/t3-code-desktop.desktop \
      $out/share/applications/t3-code.desktop
    install -Dm 444 ${appimageContents}/usr/share/icons/hicolor/1024x1024/apps/t3-code-desktop.png \
      $out/share/icons/hicolor/1024x1024/apps/t3-code.png

    substituteInPlace $out/share/applications/t3-code.desktop \
      --replace-fail 'Exec=AppRun --no-sandbox %U' 'Exec=t3-code %U' \
      --replace-fail 'Icon=t3-code-desktop' 'Icon=t3-code'
  '';

  meta = {
    description = "T3 Code desktop IDE";
    homepage = "https://github.com/pingdotgg/t3code";
    license = lib.licenses.unfree;
    mainProgram = "t3-code";
    platforms = [ "x86_64-linux" ];
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
  };
}
