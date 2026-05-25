{
  lib,
  buildNpmPackage,
  fetchFromGitHub,
  makeWrapper,
  nodejs,
  openchamberBackendMux,
  openchamberClaudeBridge,
  pkg-config,
  vips,
}:

let
  pname = "openchamber";
  version = "1.11.4";
  src = fetchFromGitHub {
    owner = "openchamber";
    repo = "openchamber";
    tag = "v${version}";
    hash = "sha256-F70V+U9OQ2/qyH8UcpIG2wHW6v8FI08s6UzT056dp1U=";
  };
  postPatch = ''
    cp ${./package.json} package.json
    cp ${./package-lock.json} package-lock.json
  '';
in
buildNpmPackage {
  inherit pname version src postPatch;

  patches = [
    ../../patches/openchamber/claude-backend-selector.patch
    ../../patches/openchamber/mixed-backend-mux.patch
    ../../patches/openchamber/desktop-popup-performance.patch
  ];

  npmDepsHash = "sha256-VTKQo3803qHYeipuT1DuVInVGeptHGicGScOGb8MBm0=";
  npmDepsFetcherVersion = 2;
  npmWorkspace = "packages/web";
  npmFlags = [ "--install-links" ];

  nativeBuildInputs = [
    makeWrapper
    pkg-config
  ];

  buildInputs = [
    vips
  ];

  installPhase = ''
    runHook preInstall

    packageOut="$out/lib/node_modules/@openchamber/web"
    mkdir -p "$packageOut" "$out/bin"

    cp packages/web/package.json "$packageOut/package.json"
    cp packages/web/README.md "$packageOut/README.md"
    cp -r packages/web/bin "$packageOut/bin"
    cp -r packages/web/dist "$packageOut/dist"
    cp -r packages/web/public "$packageOut/public"
    cp -r packages/web/server "$packageOut/server"

    npm prune --omit=dev --no-save --workspace="$npmWorkspace" --install-links

    cp -r node_modules "$packageOut/node_modules"
    find "$packageOut/node_modules" -xtype l -delete

    makeWrapper ${lib.getExe nodejs} "$out/bin/openchamber" \
      --add-flags "$packageOut/bin/cli.js" \
      --set-default OPENCHAMBER_BACKEND_MUX_BINARY "${lib.getExe openchamberBackendMux}" \
      --set-default OPENCHAMBER_CLAUDE_BRIDGE_BINARY "${lib.getExe openchamberClaudeBridge}"

    runHook postInstall
  '';

  meta = with lib; {
    description = "Browser UI and remote interface for OpenCode";
    homepage = "https://github.com/openchamber/openchamber";
    license = licenses.mit;
    mainProgram = "openchamber";
    platforms = platforms.linux;
  };
}
