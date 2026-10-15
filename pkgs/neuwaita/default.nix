{ stdenvNoCC }:

# Upstream's account was deleted and rev 112525b2 was never archived anywhere:
# this tarball, recovered from a local build, is the only copy. Irreplaceable.
stdenvNoCC.mkDerivation {
  pname = "neuwaita";
  version = "unstable-2026-03-18";
  src = ./neuwaita-112525b2.tar.xz;
  installPhase = /* bash */ ''
    runHook preInstall

    mkdir --parents $out/share/icons/Neuwaita
    cp --recursive index.theme scalable Extras $out/share/icons/Neuwaita/
    cp --recursive $out/share/icons/Neuwaita $out/share/icons/Neuwaita-KDE
    substituteInPlace $out/share/icons/Neuwaita-KDE/index.theme \
      --replace-fail 'Name=Neuwaita' 'Name=Neuwaita KDE' \
      --replace-fail 'Inherits=Adwaita,hicolor,breeze' $'Inherits=Neuwaita,breeze,Adwaita,hicolor\nFollowsColorScheme=true'

    for theme in Neuwaita Neuwaita-KDE; do
      places="$out/share/icons/$theme/scalable/places"
      ln --symbolic folder.svg "$places/folder-blue.svg"
      ln --symbolic folder-download.svg "$places/folder-downloads.svg"
      ln --symbolic user-desktop.svg "$places/folder-desktop.svg"
      ln --symbolic user-home.svg "$places/folder-home.svg"
      ln --symbolic folder.svg "$places/inode-directory.svg"
    done

    runHook postInstall
  '';
}
