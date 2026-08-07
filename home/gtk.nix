{ lib, pkgs, ... }:

let
  # Upstream (github.com/RusticBard/Neuwaita) was deleted along with its owner's
  # account, so rev 112525b2 is unfetchable and unarchived. The tarball vendored
  # here is recovered from the last local build of that rev and is now the only
  # copy of this theme; its index.theme already carries the comma-only Inherits
  # separators KDE's icon loader needs, so no normalization step is left to run.
  neuwaita = pkgs.stdenvNoCC.mkDerivation {
    pname = "neuwaita";
    version = "unstable-2026-03-18";
    src = ./neuwaita/neuwaita-112525b2.tar.xz;
    installPhase = ''
      runHook preInstall

      mkdir -p $out/share/icons/Neuwaita
      cp -r index.theme scalable Extras $out/share/icons/Neuwaita/
      cp -r $out/share/icons/Neuwaita $out/share/icons/Neuwaita-KDE
      substituteInPlace $out/share/icons/Neuwaita-KDE/index.theme \
        --replace-fail 'Name=Neuwaita' 'Name=Neuwaita KDE' \
        --replace-fail 'Inherits=Adwaita,hicolor,breeze' $'Inherits=Neuwaita,breeze,Adwaita,hicolor\nFollowsColorScheme=true'

      for theme in Neuwaita Neuwaita-KDE; do
        places="$out/share/icons/$theme/scalable/places"
        ln -s folder.svg "$places/folder-blue.svg"
        ln -s folder-download.svg "$places/folder-downloads.svg"
        ln -s user-desktop.svg "$places/folder-desktop.svg"
        ln -s user-home.svg "$places/folder-home.svg"
        ln -s folder.svg "$places/inode-directory.svg"
      done

      runHook postInstall
    '';
  };
in
{
  # Theme packages stay declarative; the theme switcher owns the active settings.
  home.packages = [
    pkgs.adw-gtk3
    pkgs.adwaita-icon-theme
    pkgs.colloid-icon-theme
    neuwaita
  ];

  # ── dconf / GNOME settings ───────────────────────────────────
  dconf.settings = {
    "org/gnome/desktop/interface" = {
      clock-format = "12h";
    };
    "org/gnome/nautilus/preferences" = {
      show-image-thumbnails = "always";
      thumbnail-limit = lib.hm.gvariant.mkUint64 100;
    };
  };
}
