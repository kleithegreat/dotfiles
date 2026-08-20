{ lib, stdenv, fetchFromGitHub, meson, ninja, makeWrapper, tcl, tclPackages, acpi }:

stdenv.mkDerivation (finalAttrs: {
  pname = "i8kutils";
  version = "1.60";

  src = fetchFromGitHub {
    owner = "Wer-Wolf";
    repo = "i8kutils";
    rev = "v${finalAttrs.version}";
    hash = "sha256-vNRi56gjVaQKS1bMbWw0MSKsf1tZcrkILGMqklQ6OLs=";
  };

  nativeBuildInputs = [ meson ninja makeWrapper ];
  buildInputs = [ tcl ];

  mesonFlags = [
    "-Dmoduledir=${placeholder "out"}/lib/tcl8/8.6"
    "-Ddefault_config=disabled"
    "-Dsystemd_support=disabled"
    "-Dsysvinit_support=disabled"
  ];

  postInstall = ''
    for bin in i8kmon i8kctl; do
      wrapProgram "$out/bin/$bin" \
        --prefix PATH : ${lib.makeBinPath [ acpi ]} \
        --set TCL8_6_TM_PATH "$out/lib/tcl8/8.6" \
        --set TCLLIBPATH "${tclPackages.tcllib}/lib"
    done
  '';

  meta = {
    description = "Fan control for Dell laptops via dell-smm-hwmon";
    homepage = "https://github.com/Wer-Wolf/i8kutils";
    license = lib.licenses.gpl3Plus;
    platforms = lib.platforms.linux;
    mainProgram = "i8kmon";
  };
})
