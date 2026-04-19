{
  lib,
  buildNpmPackage,
  fetchFromGitHub,
  makeWrapper,
  nodejs,
  openchamberClaudeBridge,
  pkg-config,
  writeShellScript,
  xdg-utils,
}:

let
  pname = "openchamber";
  version = "1.9.6";
  src = fetchFromGitHub {
    owner = "openchamber";
    repo = "openchamber";
    tag = "v${version}";
    hash = "sha256-J59zE1PbTvACcHLhHAarUp2fq9+le5O+7wkJXpPmvGo=";
  };
  postPatch = ''
    cp ${./package.json} package.json
    cp ${./package-lock.json} package-lock.json
  '';
  launcherScript = writeShellScript "openchamber-launch" ''
    set -eu

    script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
    openchamber_bin="$script_dir/openchamber"

    set +e
    output="$($openchamber_bin "$@" 2>&1)"
    status=$?
    set -e

    if [ "$status" -ne 0 ]; then
      printf '%s\n' "$output" >&2
      exit "$status"
    fi

    url=""
    case "$output" in
      *"visit: "*)
        url="''${output#*"visit: "}"
        url="''${url%%$'\n'*}"
        ;;
    esac

    if [ -n "$url" ]; then
      ${xdg-utils}/bin/xdg-open "$url" >/dev/null 2>&1 &
    fi
  '';
in
buildNpmPackage {
  inherit pname version src postPatch;

  patches = [
    ../../patches/openchamber/claude-backend-selector.patch
  ];

  npmDepsHash = "sha256-Gy1dxncCuMgpsom83lzBkoSYayBWiZfIS7LaHbnNzAA=";
  npmDepsFetcherVersion = 2;
  npmWorkspace = "packages/web";
  npmFlags = [ "--install-links" ];

  nativeBuildInputs = [
    makeWrapper
    pkg-config
  ];

  installPhase = ''
    runHook preInstall

    packageOut="$out/lib/node_modules/@openchamber/web"
    mkdir -p "$packageOut" \
      "$out/bin" \
      "$out/share/applications" \
      "$out/share/icons/hicolor/192x192/apps" \
      "$out/share/pixmaps"

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
      --set-default OPENCHAMBER_CLAUDE_BRIDGE_BINARY "${lib.getExe openchamberClaudeBridge}"

    install -m 0644 packages/web/public/pwa-192.png \
      "$out/share/icons/hicolor/192x192/apps/openchamber.png"
    ln -s ../icons/hicolor/192x192/apps/openchamber.png \
      "$out/share/pixmaps/openchamber.png"

    desktopFile="$out/share/applications/openchamber.desktop"
    printf '%s\n' \
      '[Desktop Entry]' \
      'Version=1.0' \
      'Type=Application' \
      'Name=OpenChamber' \
      'Comment=Run OpenCode in your browser' \
      "Exec=$out/bin/openchamber-launch" \
      'Icon=openchamber' \
      'Categories=Development;' \
      'Keywords=OpenCode;AI;Assistant;' \
      'Terminal=false' \
      > "$desktopFile"

    install -m 0755 ${launcherScript} "$out/bin/openchamber-launch"

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
