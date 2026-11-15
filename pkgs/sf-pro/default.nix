{ lib, stdenvNoCC, fetchurl, p7zip, cpio }:

stdenvNoCC.mkDerivation {
  pname = "sf-pro";
  version = "2026-11-04";

  # Apple rotates these bytes: refresh version and hash together, and re-check the layout with `7z l`.
  src = fetchurl {
    url = "https://devimages-cdn.apple.com/design/resources/download/SF-Pro.dmg";
    hash = "sha256-sn/mYi8fqWpwfHPcpmZtQ5w1sxLVsdR+DimA5hjrSyg=";
  };

  nativeBuildInputs = [
    p7zip
    cpio
  ];

  setSourceRoot = "sourceRoot=$PWD";

  # 7z unwraps dmg -> hfs -> pkg -> gzip down to the cpio payload.
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
