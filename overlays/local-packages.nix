final: prev: {
  desktopctl = final.callPackage ../desktopctl { };
  helium = final.callPackage ../pkgs/helium { };
  sf-pro = final.stdenvNoCC.mkDerivation {
    pname = "sf-pro";
    version = "2026-02-05";

    src = final.fetchurl {
      url = "https://devimages-cdn.apple.com/design/resources/download/SF-Pro.dmg";
      hash = "sha256-s42hsaUe0Vkaw5yw8G7G3W3AYJb2TPqSlMqPyY0e5WU=";
    };

    nativeBuildInputs = [
      final.p7zip
      final.cpio
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

    meta = with final.lib; {
      description = "Apple San Francisco Pro fonts";
      homepage = "https://developer.apple.com/fonts/";
      license = licenses.unfree;
      platforms = platforms.all;
    };
  };
  lmstudio = prev.lmstudio.overrideAttrs (old: {
    buildCommand = final.lib.replaceStrings
      [
        "/usr/share/icons/hicolor/0x0/apps/lm-studio.png"
        "install -m 755 /nix/store/dg79mm2j98n2ry1fdqkygrvnpg83mdlw-lmstudio-0.4.10-1-extracted/resources/app/.webpack/lms $out/bin/"
        "patchelf --set-interpreter "
      ]
      [
        "/resources/app/.webpack/Icon-512x512.png"
        "if [ -s /nix/store/dg79mm2j98n2ry1fdqkygrvnpg83mdlw-lmstudio-0.4.10-1-extracted/resources/app/.webpack/lms ]; then install -m 755 /nix/store/dg79mm2j98n2ry1fdqkygrvnpg83mdlw-lmstudio-0.4.10-1-extracted/resources/app/.webpack/lms $out/bin/; fi"
        "test ! -s $out/bin/lms || patchelf --set-interpreter "
      ]
      old.buildCommand;
  });
}
