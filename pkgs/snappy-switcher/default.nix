{ lib, stdenv, fetchFromGitHub, pkg-config, wayland-scanner, wayland, wayland-protocols, cairo, pango, json_c, libxkbcommon, glib, librsvg, gdk-pixbuf }:

stdenv.mkDerivation {
  pname = "snappy-switcher";
  version = "4.0.0";

  src = fetchFromGitHub {
    owner = "OpalAayan";
    repo = "snappy-switcher";
    rev = "v4.0.0";
    hash = "sha256-TadQupTY8uu46KAyrcsEWSgOija5Qgt4x9zXK7rJzUE=";
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

  buildPhase = ''
    runHook preBuild
    make
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p $out/bin
    mkdir -p $out/share/snappy-switcher/themes
    mkdir -p $out/share/doc/snappy-switcher

    install -m 755 snappy-switcher $out/bin/
    install -m 644 themes/*.ini $out/share/snappy-switcher/themes/
    install -m 644 config.ini.example $out/share/doc/snappy-switcher/
    install -m 644 README.md $out/share/doc/snappy-switcher/ || true

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
