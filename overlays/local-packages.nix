final: prev: {
  bambu-studio =
    let
      pname = "bambu-studio";
      version = "02.05.00.67";
      caBundle = "${final.cacert}/etc/ssl/certs/ca-bundle.crt";
      fontsConf = final.makeFontsConf { fontDirectories = [ final.nanum ]; };
      appimageContents = final.appimageTools.extract {
        inherit pname version;
        src = bambuStudioAppImage;
      };
      bambuStudioAppImage = final.fetchurl {
        url = "https://github.com/bambulab/BambuStudio/releases/download/v${version}/Bambu_Studio_linux_fedora-v02.05.00.66.AppImage";
        hash = "sha256-ydurwaGx3+AfA64oY1OZ7X3RoLjqbZcyvy2Ro5OBsK0=";
      };
    in
      final.appimageTools.wrapType2 {
        inherit pname version;
        src = bambuStudioAppImage;

        profile = ''
          export SSL_CERT_FILE="${caBundle}"
          export CURL_CA_BUNDLE="${caBundle}"
          export GIO_MODULE_DIR="${final.glib-networking}/lib/gio/modules"
          export WEBKIT_DISABLE_COMPOSITING_MODE=1
          export WEBKIT_DISABLE_DMABUF_RENDERER=1
          export FONTCONFIG_FILE="${fontsConf}"
        '';

        extraPkgs = pkgs: with pkgs; [
          cacert
          glib
          glib-networking
          gst_all_1.gst-plugins-bad
          gst_all_1.gst-plugins-base
          gst_all_1.gst-plugins-good
          libsecret
          webkitgtk_4_1
        ];

        extraInstallCommands = ''
          install -m 444 -D ${appimageContents}/BambuStudio.desktop \
            $out/share/applications/BambuStudio.desktop
          install -m 444 -D ${appimageContents}/BambuStudio.png \
            $out/share/icons/hicolor/scalable/apps/BambuStudio.png
          substituteInPlace $out/share/applications/BambuStudio.desktop \
            --replace-fail 'Exec=AppRun %U' 'Exec=bambu-studio %U'
        '';

        meta = prev.bambu-studio.meta // {
          mainProgram = "bambu-studio";
          sourceProvenance = with final.lib.sourceTypes; [ binaryNativeCode ];
        };
      };

  desktopctl = final.callPackage ../desktopctl { };
  helium = final.callPackage ../pkgs/helium { };
  snappy-switcher = final.callPackage ../pkgs/snappy-switcher { };
  openchamber-backend-mux = final.callPackage ../pkgs/openchamber-backend-mux { };
  openchamber-claude-bridge = final.callPackage ../pkgs/openchamber-claude-bridge { };
  openchamber-cli = final.callPackage ../pkgs/openchamber/cli.nix {
    openchamberBackendMux = final.openchamber-backend-mux;
    openchamberClaudeBridge = final.openchamber-claude-bridge;
  };
  openchamber-desktop = final.callPackage ../pkgs/openchamber-desktop {
    openchamberCli = final.openchamber-cli;
  };
  openchamber = final.callPackage ../pkgs/openchamber {
    openchamberCli = final.openchamber-cli;
    openchamberDesktop = final.openchamber-desktop;
  };
  sf-pro = final.stdenvNoCC.mkDerivation {
    pname = "sf-pro";
    version = "2026-05-23";

    src = final.fetchurl {
      url = "https://devimages-cdn.apple.com/design/resources/download/SF-Pro.dmg";
      hash = "sha256-W0sZkipBtrduInk0oocbFAXX1qy0Z+yk2xUyFfDWx4s=";
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
}
