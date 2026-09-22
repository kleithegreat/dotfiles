{ lib, stdenvNoCC, fetchurl, p7zip, cpio }:

stdenvNoCC.mkDerivation {
  pname = "sf-pro";
  version = "2026-09-14";

  # Apple rotates the bytes behind this stable URL; refresh version + hash
  # together when the fixed-output fetch starts failing, and re-check the
  # archive layout -- the inner package name has changed across rotations.
  src = fetchurl {
    url = "https://devimages-cdn.apple.com/design/resources/download/SF-Pro.dmg";
    hash = "sha256-loqzuLH5LC2K9h6waA9cIiTE541ZuYa/AEUCp/wBKRg=";
  };

  nativeBuildInputs = [
    p7zip
    cpio
  ];

  setSourceRoot = "sourceRoot=$PWD";

  # 7z walks the whole dmg -> hfs -> pkg -> gzip chain on its own and lands on
  # the bare cpio payload.
  unpackPhase = ''
    runHook preUnpack

    7z x "$src"
    mkdir payload
    cpio -id --quiet -D payload < Payload~

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
