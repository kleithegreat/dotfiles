final: prev: {
  cantarell-fonts = prev.cantarell-fonts.overrideAttrs (old: {
    # The variable OTF autohint step fails on the current nixpkgs pin; static
    # OTFs preserve the family without depending on that broken target.
    mesonFlags = (old.mesonFlags or []) ++ [
      "-Dbuildvf=false"
      "-Dbuildstatics=true"
    ];
  });

  lmstudio =
    let
      pname = "lmstudio";
      version = "0.4.20-1";
      src = final.fetchurl {
        url = "https://installers.lmstudio.ai/linux/x64/${version}/LM-Studio-${version}-x64.AppImage";
        hash = "sha256-bhyeeXOuiS7vk01wZhLJIMBLJBZYYRCNWIMliAHGSu0=";
      };
      appimageContents = final.appimageTools.extract {
        inherit pname version src;
      };
    in
      final.appimageTools.wrapType2 {
        inherit pname version src;

        nativeBuildInputs = [ final.graphicsmagick ];

        extraPkgs = pkgs: [ pkgs.ocl-icd ];

        extraInstallCommands = ''
          mkdir -p $out/share/applications

          src_icon="${appimageContents}/usr/share/icons/hicolor/0x0/apps/lm-studio.png"
          sizes=("16x16" "32x32" "48x48" "64x64" "128x128" "256x256")
          for size in "''${sizes[@]}"; do
            install -dm755 "$out/share/icons/hicolor/$size/apps"
            gm convert "$src_icon" -resize "$size" "$out/share/icons/hicolor/$size/apps/lm-studio.png"
          done

          install -m 444 -D ${appimageContents}/lm-studio.desktop -t $out/share/applications

          mv $out/bin/lmstudio $out/bin/lm-studio

          install -m 755 -D /dev/stdin $out/bin/lm-studio-desktop <<EOF
          #!${final.runtimeShell}
          "$out/bin/lm-studio" "\$@"
          EOF

          substituteInPlace $out/share/applications/lm-studio.desktop \
            --replace-fail 'Exec=AppRun --no-sandbox %U' "Exec=$out/bin/lm-studio-desktop %U"

          install -m 755 ${appimageContents}/resources/app/.webpack/lms $out/bin/
          patchelf --set-interpreter "${final.stdenv.cc.bintools.dynamicLinker}" $out/bin/lms
        '';

        meta = prev.lmstudio.meta // {
          mainProgram = "lm-studio";
          sourceProvenance = with final.lib.sourceTypes; [ binaryNativeCode ];
        };
      };

  bambu-studio =
    let
      pname = "bambu-studio";
      version = "02.07.01.62";
      caBundle = "${final.cacert}/etc/ssl/certs/ca-bundle.crt";
      fontsConf = final.makeFontsConf { fontDirectories = [ final.nanum ]; };
      appimageContents = final.appimageTools.extract {
        inherit pname version;
        src = bambuStudioAppImage;
      };
      bambuStudioAppImage = final.fetchurl {
        url = "https://github.com/bambulab/BambuStudio/releases/download/v${version}/BambuStudio_ubuntu24.04-v${version}-20260616195227.AppImage";
        hash = "sha256-+pi2CFMt+7uysJMUg6rEHlf7GcF1osx719Uo1eD7soc=";
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
          install -m 755 -D /dev/stdin $out/bin/bambu-studio-desktop <<EOF
          #!${final.runtimeShell}
          "$out/bin/bambu-studio" "\$@"
          EOF
          substituteInPlace $out/share/applications/BambuStudio.desktop \
            --replace-fail 'Exec=AppRun %U' "Exec=$out/bin/bambu-studio-desktop %U" \
            --replace-fail 'StartupWMClass=bambu-studio' 'StartupWMClass=BambuStudio'
        '';

        meta = prev.bambu-studio.meta // {
          mainProgram = "bambu-studio";
          sourceProvenance = with final.lib.sourceTypes; [ binaryNativeCode ];
        };
      };

  desktopctl = final.callPackage ../desktopctl { };
  helium = final.callPackage ../pkgs/helium { };
  snappy-switcher = final.callPackage ../pkgs/snappy-switcher { };
  openchamber-backend-mux = final.callPackage ../pkgs/openchamber-backend-mux {
    openchamberClaudeBridge = final.openchamber-claude-bridge;
  };
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
    version = "2026-06-13";

    src = final.fetchurl {
      url = "https://devimages-cdn.apple.com/design/resources/download/SF-Pro.dmg";
      hash = "sha256-YxGk8IQ6TS5hagsFx3US0x0uqVBFnPUmzbW5CZageU8=";
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
