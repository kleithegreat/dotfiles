{ stdenvNoCC, kdePackages }:

# The only copy: upstream's account is gone and rev 112525b2 was never archived.
stdenvNoCC.mkDerivation {
  pname = "neuwaita";
  version = "unstable-2026-03-18";
  src = ./neuwaita-112525b2.tar.xz;
  # QtSvg paints definitions left outside <defs>, here a black backdrop.
  postPatch = /* bash */ ''
    sed --in-place --regexp-extended \
      --expression='s:<(clipPath|filter|mask) :<defs>&:' \
      --expression='s:</(clipPath|filter|mask)>:&</defs>:' \
      scalable/places/user-trash.svg
  '';
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

    # Inherited actions lose to this theme's generics (docs/theming.md).
    for size in 16 22 24 32; do
      mkdir --parents "$out/share/icons/Neuwaita-KDE/''${size}x$size"
      ln --symbolic ${kdePackages.breeze-icons}/share/icons/breeze/actions/$size \
        "$out/share/icons/Neuwaita-KDE/''${size}x$size/actions"
    done

    runHook postInstall
  '';
}
