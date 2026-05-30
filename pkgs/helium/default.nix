{
  lib,
  stdenv,
  fetchurl,
  autoPatchelfHook,
  makeWrapper,
  adwaita-icon-theme,
  alsa-lib,
  atk,
  at-spi2-atk,
  at-spi2-core,
  cairo,
  cups,
  dbus,
  expat,
  gsettings-desktop-schemas,
  glib,
  gtk3,
  gtk4,
  hicolor-icon-theme,
  krb5,
  libGL,
  libpulseaudio,
  libva,
  libxcb,
  libxkbcommon,
  libX11,
  libXcomposite,
  libXdamage,
  libXext,
  libXfixes,
  libXrandr,
  mesa,
  nspr,
  nss,
  pango,
  pipewire,
  qt6,
  systemd,
  wayland,
  xdg-utils,
}:

let
  source = import ./source.nix;
  version = source.version;
  releaseAsset = "helium-${version}-x86_64_linux.tar.xz";
  runtimeLibraryPath = lib.makeLibraryPath [
    libGL
    libva
    pipewire
    libpulseaudio
    gtk3
    gtk4
    wayland
    krb5
  ];
  runtimeDataDirs = lib.concatStringsSep ":" [
    "${cups}/share"
    "${gtk3}/share"
    "${gtk4}/share"
    "${adwaita-icon-theme}/share"
    "${hicolor-icon-theme}/share"
    "${gsettings-desktop-schemas}/share/gsettings-schemas/${gsettings-desktop-schemas.name}"
    "${gtk3}/share/gsettings-schemas/${gtk3.name}"
    "${gtk4}/share/gsettings-schemas/${gtk4.name}"
  ];
in
assert lib.assertMsg (stdenv.hostPlatform.system == "x86_64-linux")
  "pkgs.helium is currently packaged only for x86_64-linux.";
stdenv.mkDerivation {
  pname = "helium";
  inherit version;

  src = fetchurl {
    url = "https://github.com/imputnet/helium-linux/releases/download/${version}/${releaseAsset}";
    sha256 = source.sha256;
  };

  nativeBuildInputs = [
    autoPatchelfHook
    makeWrapper
  ];

  # Determined from the shipped ELF NEEDED entries in the upstream tarball,
  # plus the Qt6 shim that Helium bundles for desktop integration.
  buildInputs = [
    alsa-lib
    atk
    at-spi2-atk
    at-spi2-core
    cairo
    cups
    dbus
    expat
    glib
    libxcb
    libxkbcommon
    libX11
    libXcomposite
    libXdamage
    libXext
    libXfixes
    libXrandr
    mesa
    nspr
    nss
    pango
    qt6.qtbase
    stdenv.cc.cc.lib
    systemd
  ];

  autoPatchelfIgnoreMissingDeps = [
    "libQt5Core.so.5"
    "libQt5Gui.so.5"
    "libQt5Widgets.so.5"
  ];

  dontConfigure = true;
  dontBuild = true;
  dontWrapQtApps = true;

  installPhase = ''
    runHook preInstall

    install -d "$out/bin" \
      "$out/libexec/helium" \
      "$out/share/applications" \
      "$out/share/icons/hicolor/256x256/apps" \
      "$out/share/pixmaps"

    cp -a ./* "$out/libexec/helium/"

    substituteInPlace "$out/libexec/helium/helium-wrapper" \
      --replace-fail 'CHROME_VERSION_EXTRA="custom"' 'CHROME_VERSION_EXTRA="nixos"'

    makeWrapper "$out/libexec/helium/helium-wrapper" "$out/bin/helium" \
      --prefix LD_LIBRARY_PATH : "${runtimeLibraryPath}" \
      --prefix XDG_DATA_DIRS : "${runtimeDataDirs}" \
      --suffix PATH : "${lib.makeBinPath [ xdg-utils ]}"

    install -m 0644 "$out/libexec/helium/helium.desktop" \
      "$out/share/applications/helium.desktop"
    install -m 0644 "$out/libexec/helium/product_logo_256.png" \
      "$out/share/icons/hicolor/256x256/apps/helium.png"
    ln -s ../icons/hicolor/256x256/apps/helium.png "$out/share/pixmaps/helium.png"

    runHook postInstall
  '';

  meta = with lib; {
    description = "Private, fast, and honest web browser";
    homepage = "https://github.com/imputnet/helium-linux";
    license = licenses.gpl3Only;
    mainProgram = "helium";
    platforms = [ "x86_64-linux" ];
    sourceProvenance = with sourceTypes; [ binaryNativeCode ];
  };
}
