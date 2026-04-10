final: prev: {
  desktopctl = final.callPackage ../desktopctl { };
  helium = final.callPackage ../pkgs/helium { };
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
