{ lib, stdenv, fetchFromGitHub, pkg-config, wayland-scanner, wayland, wayland-protocols, cairo, pango, json_c, libxkbcommon, glib, librsvg, gdk-pixbuf }:

stdenv.mkDerivation {
  pname = "snappy-switcher";
  version = "4.5.0";

  src = fetchFromGitHub {
    owner = "OpalAayan";
    repo = "snappy-switcher";
    rev = "v4.5.0";
    hash = "sha256-HH7Pmw6LHJhuV07FOsVlyZNwztZgz4IRi6XT5G+qroA=";
  };

  nativeBuildInputs = [
    pkg-config
    wayland-scanner
  ];

  buildInputs = [
    wayland
    wayland-protocols
    cairo
    pango
    json_c
    libxkbcommon
    glib
    librsvg
    gdk-pixbuf
  ];

  installPhase = /* bash */ ''
    runHook preInstall

    install -D --mode=755 snappy-switcher --target-directory=$out/bin
    install -D --mode=644 themes/*.ini --target-directory=$out/share/snappy-switcher/themes

    runHook postInstall
  '';

  meta = with lib; {
    description = "A fast, keyboard-driven window switcher for Wayland compositors";
    homepage = "https://github.com/OpalAayan/snappy-switcher";
    license = licenses.gpl3Only;
    platforms = platforms.linux;
    mainProgram = "snappy-switcher";
  };
}
