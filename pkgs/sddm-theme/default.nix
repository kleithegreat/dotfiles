{ lib, runCommandLocal }:

let
  themeDir = "/var/lib/desktopctl/sddm";
  backgroundPath = "${themeDir}/background";
  configPath = "${themeDir}/theme.conf";
in
runCommandLocal "sddm-theme" {
  passthru = {
    inherit themeDir backgroundPath configPath;
  };
  meta = {
    description = "Minimal Qt6 SDDM theme synced with desktopctl";
    platforms = lib.platforms.linux;
  };
} /* bash */ ''
  dir="$out/share/sddm/themes/desktopctl"
  install -D --mode=0644 ${./metadata.desktop} "$dir/metadata.desktop"
  install -D --mode=0644 ${./Main.qml} "$dir/Main.qml"
  install -D --mode=0644 ${./theme.conf} "$dir/theme.conf"
  ln --symbolic ${configPath} "$dir/theme.conf.user"
''
