{
  lib,
  stdenvNoCC,
  makeWrapper,
  claude-code,
  nodejs,
}:

stdenvNoCC.mkDerivation {
  pname = "openchamber-claude-bridge";
  version = "0.1.0";

  src = ./.;

  nativeBuildInputs = [ makeWrapper ];

  dontBuild = true;

  installPhase = ''
    runHook preInstall

    mkdir -p "$out/bin" "$out/libexec/openchamber-claude-bridge"
    cp ${./index.mjs} "$out/libexec/openchamber-claude-bridge/index.mjs"

    makeWrapper ${lib.getExe nodejs} "$out/bin/openchamber-claude-bridge" \
      --add-flags "$out/libexec/openchamber-claude-bridge/index.mjs" \
      --set-default CLAUDE_CODE_BIN "${lib.getExe claude-code}"

    runHook postInstall
  '';

  meta = with lib; {
    description = "OpenCode-compatible bridge that drives Claude Code for OpenChamber";
    homepage = "https://github.com/openchamber/openchamber";
    license = licenses.mit;
    mainProgram = "openchamber-claude-bridge";
    platforms = platforms.linux;
  };
}
