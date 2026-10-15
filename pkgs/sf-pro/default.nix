{ lib, stdenvNoCC, fetchurl, p7zip, cpio }:

stdenvNoCC.mkDerivation {
  pname = "sf-pro";
  version = "2026-09-14";

  # Apple rotates the bytes behind this URL: refresh version and hash together,
  # and re-check the unpack against `7z l`, since the inner layout moves too.
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
  unpackPhase = /* bash */ ''
    runHook preUnpack

    7z x "$src"
    mkdir payload
    cpio --extract --make-directories --quiet --directory=payload < Payload~

    runHook postUnpack
  '';

  installPhase = /* bash */ ''
    runHook preInstall

    mkdir --parents "$out/share/fonts/opentype" "$out/share/fonts/truetype"
    find payload -type f -name '*.otf' -exec mv --target-directory="$out/share/fonts/opentype" {} +
    find payload -type f -name '*.ttf' -exec mv --target-directory="$out/share/fonts/truetype" {} +

    runHook postInstall
  '';

  meta = with lib; {
    description = "Apple San Francisco Pro fonts";
    homepage = "https://developer.apple.com/fonts/";
    license = licenses.unfree;
    platforms = platforms.all;
  };
}
