{ lib, stdenvNoCC, fetchurl, p7zip, cpio }:

stdenvNoCC.mkDerivation {
  pname = "sf-pro";
  version = "2026-08-08";

  # Apple rotates the bytes behind this stable URL; refresh version + hash
  # together when the fixed-output fetch starts failing.
  src = fetchurl {
    url = "https://devimages-cdn.apple.com/design/resources/download/SF-Pro.dmg";
    hash = "sha256-qQlPDem3idc1RO5Q/FKgiE1Kn3/PYt5Sl04yBPOnSmI=";
  };

  nativeBuildInputs = [
    p7zip
    cpio
  ];

  setSourceRoot = "sourceRoot=$PWD";

  unpackPhase = ''
    runHook preUnpack

    7z x "$src"
    pkg_path="$(find . -maxdepth 2 -type f -name 'SF Pro Fonts.pkg' -print -quit)"
    if [ -z "$pkg_path" ]; then
      echo "failed to locate SF Pro Fonts.pkg in Apple DMG" >&2
      exit 1
    fi

    7z x "$pkg_path"

    mkdir payload
    if cpio -it --quiet < Payload~ > /dev/null 2>&1; then
      cpio -id --quiet -D payload < Payload~
    else
      7z x Payload~ -opayload
    fi

    runHook postUnpack
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p "$out/share/fonts/opentype" "$out/share/fonts/truetype"
    find payload -type f -name '*.otf' -exec mv -t "$out/share/fonts/opentype" {} +
    find payload -type f -name '*.ttf' -exec mv -t "$out/share/fonts/truetype" {} +

    runHook postInstall
  '';

  meta = with lib; {
    description = "Apple San Francisco Pro fonts";
    homepage = "https://developer.apple.com/fonts/";
    license = licenses.unfree;
    platforms = platforms.all;
  };
}
