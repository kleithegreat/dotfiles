{
  lib,
  stdenv,
  fetchurl,
  autoPatchelfHook,
}:

let
  version = "0.2.5";
  bundle = "dd-cli-v${version}-linux-amd64";
in
stdenv.mkDerivation {
  pname = "dd-cli";
  inherit version;

  src = fetchurl {
    url = "https://github.com/doordash-oss/doordash-cli/releases/download/v${version}/${bundle}.tar.gz";
    hash = "sha256-yu+PNFCxHG6MD/yhbjNbf6dKbQvGc+NN3SI5UoyWYp0=";
  };

  nativeBuildInputs = [ autoPatchelfHook ];

  dontConfigure = true;
  dontBuild = true;
  # PyInstaller appends its archive to the executable; a stripped one segfaults.
  dontStrip = true;

  installPhase = /* bash */ ''
    runHook preInstall

    install --directory "$out/bin" "$out/libexec"
    cp --archive . "$out/libexec/dd-cli"
    ln --symbolic "$out/libexec/dd-cli/${bundle}" "$out/bin/dd-cli"

    runHook postInstall
  '';

  meta = with lib; {
    description = "DoorDash's command-line client for searching stores and placing orders";
    homepage = "https://github.com/doordash-oss/doordash-cli";
    license = licenses.unfree;
    mainProgram = "dd-cli";
    platforms = [ "x86_64-linux" ];
    sourceProvenance = with sourceTypes; [ binaryNativeCode ];
  };
}
