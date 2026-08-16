{ lib
, appimageTools
, fetchurl
, cacert
, glib-networking
, makeFontsConf
, nanum
, runtimeShell
, upstreamBambuStudio
}:

let
  pname = "bambu-studio";
  version = "02.08.02.60";
  caBundle = "${cacert}/etc/ssl/certs/ca-bundle.crt";
  fontsConf = makeFontsConf { fontDirectories = [ nanum ]; };
  bambuStudioAppImage = fetchurl {
    url = "https://github.com/bambulab/BambuStudio/releases/download/v${version}/BambuStudio_ubuntu24.04-v${version}-20260814171356.AppImage";
    hash = "sha256-t40lJ6IO6fvPcO6CE4w7PKcHqpxmJYgWKdspYnJSrMM=";
  };
  appimageContents = appimageTools.extract {
    inherit pname version;
    src = bambuStudioAppImage;
  };
in
appimageTools.wrapType2 {
  inherit pname version;
  src = bambuStudioAppImage;

  profile = ''
    export SSL_CERT_FILE="${caBundle}"
    export CURL_CA_BUNDLE="${caBundle}"
    export GIO_MODULE_DIR="${glib-networking}/lib/gio/modules"
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

  # Shell-parent launcher plus the real BambuStudio window class; see the
  # AppImage/Vicinae quirk in docs/nix.md.
  extraInstallCommands = ''
    install -m 444 -D ${appimageContents}/BambuStudio.desktop \
      $out/share/applications/BambuStudio.desktop
    install -m 444 -D ${appimageContents}/BambuStudio.png \
      $out/share/icons/hicolor/scalable/apps/BambuStudio.png
    install -m 755 -D /dev/stdin $out/bin/bambu-studio-desktop <<EOF
    #!${runtimeShell}
    "$out/bin/bambu-studio" "\$@"
    EOF
    substituteInPlace $out/share/applications/BambuStudio.desktop \
      --replace-fail 'Exec=AppRun %U' "Exec=$out/bin/bambu-studio-desktop %U" \
      --replace-fail 'StartupWMClass=bambu-studio' 'StartupWMClass=BambuStudio'
  '';

  meta = upstreamBambuStudio.meta // {
    mainProgram = "bambu-studio";
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
  };
}
