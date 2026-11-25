{
  lib,
  stdenvNoCC,
  fetchurl,
  makeWrapper,
  addDriverRunpath,
}:

stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "srbminer";
  version = "3.9.0";

  src = fetchurl {
    url = "https://github.com/doktor83/SRBMiner-Multi/releases/download/${finalAttrs.version}/SRBMiner-Multi-${lib.strings.replaceStrings [ "." ] [ "-" ] finalAttrs.version}-Linux.tar.gz";
    hash = "sha256-l94VJROrJWv1fZZrrDUmhAP7VanxhLVThGITNQeQqno=";
  };

  nativeBuildInputs = [ makeWrapper ];

  # Packed: patchelf cannot touch it and it refuses buildFHSEnv's sandbox, so it runs through nix-ld.
  dontFixup = true;

  installPhase = /* bash */ ''
    runHook preInstall
    install -D --mode=0755 SRBMiner-MULTI $out/libexec/srbminer
    makeWrapper $out/libexec/srbminer $out/bin/srbminer \
      --prefix LD_LIBRARY_PATH : ${addDriverRunpath.driverLink}/lib
    runHook postInstall
  '';

  meta = {
    description = "CPU and GPU miner for Pearl, RandomX and other algorithms";
    homepage = "https://github.com/doktor83/SRBMiner-Multi";
    license = lib.licenses.unfree;
    mainProgram = "srbminer";
    platforms = [ "x86_64-linux" ];
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
})
