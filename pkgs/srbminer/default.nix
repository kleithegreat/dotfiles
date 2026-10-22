{
  lib,
  stdenvNoCC,
  fetchzip,
  makeWrapper,
  addDriverRunpath,
}:

stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "srbminer";
  version = "3.7.9";

  src = fetchzip {
    url = "https://github.com/doktor83/SRBMiner-Multi/releases/download/${finalAttrs.version}/SRBMiner-Multi-${lib.strings.replaceStrings [ "." ] [ "-" ] finalAttrs.version}-Linux.tar.gz";
    hash = "sha256-wrlSSerPk8OrFI476MTk1mTjW8TEflWZu4grzYQXCpg=";
  };

  nativeBuildInputs = [ makeWrapper ];

  # The executable is packed, so patchelf cannot touch it, and it refuses to
  # start inside buildFHSEnv's sandbox. It runs unpatched through nix-ld.
  dontFixup = true;

  installPhase = /* bash */ ''
    runHook preInstall
    install -D --mode=0755 SRBMiner-MULTI $out/libexec/srbminer
    makeWrapper $out/libexec/srbminer $out/bin/srbminer \
      --prefix LD_LIBRARY_PATH : ${addDriverRunpath.driverLink}/lib
    runHook postInstall
  '';

  meta = with lib; {
    description = "CPU and GPU miner for Pearl, RandomX and other algorithms";
    homepage = "https://github.com/doktor83/SRBMiner-Multi";
    license = licenses.unfree;
    mainProgram = "srbminer";
    platforms = [ "x86_64-linux" ];
    sourceProvenance = with sourceTypes; [ binaryNativeCode ];
  };
})
