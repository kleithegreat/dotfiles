{
  lib,
  stdenvNoCC,
  makeWrapper,
  nodejs,
}:

stdenvNoCC.mkDerivation {
  pname = "openchamber-backend-mux";
  version = "0.1.0";

  src = ./.;

  nativeBuildInputs = [ makeWrapper ];

  dontBuild = true;

  installPhase = ''
    runHook preInstall

    mkdir -p "$out/bin" "$out/libexec/openchamber-backend-mux"
    cp ${./index.mjs} "$out/libexec/openchamber-backend-mux/index.mjs"

    makeWrapper ${lib.getExe nodejs} "$out/bin/openchamber-backend-mux" \
      --add-flags "$out/libexec/openchamber-backend-mux/index.mjs"

    runHook postInstall
  '';

  meta = with lib; {
    description = "OpenChamber backend mux for OpenCode and Claude Code";
    homepage = "https://github.com/openchamber/openchamber";
    license = licenses.mit;
    mainProgram = "openchamber-backend-mux";
    platforms = platforms.linux;
  };
}
