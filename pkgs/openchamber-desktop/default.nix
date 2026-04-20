{
  lib,
  copyDesktopItems,
  glib-networking,
  gtk3,
  makeDesktopItem,
  pkg-config,
  rustPlatform,
  webkitgtk_4_1,
  wrapGAppsHook4,
  openchamberCli,
}:

rustPlatform.buildRustPackage {
  pname = "openchamber-desktop";
  version = "1.9.6";
  src = ./.;

  cargoLock.lockFile = ./Cargo.lock;

  postPatch = ''
    mkdir -p icons
    cp \
      "${openchamberCli}/lib/node_modules/@openchamber/web/public/pwa-192.png" \
      icons/icon.png
  '';

  nativeBuildInputs = [
    copyDesktopItems
    pkg-config
    wrapGAppsHook4
  ];

  buildInputs = [
    glib-networking
    gtk3
    webkitgtk_4_1
  ];

  desktopItems = [
    (makeDesktopItem {
      name = "openchamber";
      desktopName = "OpenChamber";
      comment = "Run OpenChamber in a desktop window";
      exec = "openchamber-desktop";
      icon = "openchamber";
      terminal = false;
      categories = [ "Development" ];
      keywords = [ "OpenCode" "OpenChamber" "AI" "Assistant" ];
    })
  ];

  doCheck = false;

  preFixup = ''
    gappsWrapperArgs+=(
      --set-default OPENCHAMBER_BINARY "${lib.getExe openchamberCli}"
      --set-default GIO_MODULE_DIR "${glib-networking}/lib/gio/modules"
    )
  '';

  postInstall = ''
    mkdir -p "$out/share/icons/hicolor/192x192/apps" "$out/share/pixmaps"
    install -m 0644 \
      "${openchamberCli}/lib/node_modules/@openchamber/web/public/pwa-192.png" \
      "$out/share/icons/hicolor/192x192/apps/openchamber.png"
    ln -s ../icons/hicolor/192x192/apps/openchamber.png \
      "$out/share/pixmaps/openchamber.png"
  '';

  meta = with lib; {
    description = "Desktop shell for the local OpenChamber server";
    homepage = "https://github.com/openchamber/openchamber";
    license = licenses.mit;
    mainProgram = "openchamber-desktop";
    platforms = platforms.linux;
  };
}
