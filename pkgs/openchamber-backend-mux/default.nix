{
  lib,
  stdenvNoCC,
  makeWrapper,
  nodejs,
  opencode,
  openchamberClaudeBridge,
}:

stdenvNoCC.mkDerivation {
  pname = "openchamber-backend-mux";
  version = "0.1.0";

  src = ./.;

  nativeBuildInputs = [ makeWrapper ];

  dontBuild = true;
  doCheck = true;

  checkPhase = ''
    runHook preCheck

    ${lib.getExe nodejs} --test index.test.mjs

    runHook postCheck
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p "$out/bin" "$out/libexec/openchamber-backend-mux"
    cp index.mjs "$out/libexec/openchamber-backend-mux/index.mjs"

    makeWrapper ${lib.getExe nodejs} "$out/bin/openchamber-backend-mux" \
      --add-flags "$out/libexec/openchamber-backend-mux/index.mjs" \
      --set-default OPENCHAMBER_BACKEND_MUX_OPENCODE_BINARY "${lib.getExe opencode}" \
      --set-default OPENCHAMBER_CLAUDE_BRIDGE_BINARY "${lib.getExe openchamberClaudeBridge}"

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
