{
  lib,
  buildFHSEnv,
  fetchzip,
}:

let
  version = "1.23.2";
  # Rigel hashes its own executable and exits 1 silently if it differs, so it
  # runs unpatched inside an FHS env rather than through autoPatchelf.
  src = fetchzip {
    url = "https://github.com/rigelminer/rigel/releases/download/${version}/rigel-${version}-linux.tar.gz";
    hash = "sha256-tXg7vETwJhr8Lvq7RlKCsILLR2DABTYxOH4H0vd9VcQ=";
  };
in
buildFHSEnv {
  pname = "rigel";
  inherit version;

  targetPkgs = pkgs: [ pkgs.stdenv.cc.cc.lib ];
  runScript = "${src}/rigel";

  meta = with lib; {
    description = "NVIDIA GPU miner for Octopus, KawPow, Autolykos and other algorithms";
    homepage = "https://github.com/rigelminer/rigel";
    license = licenses.unfree;
    mainProgram = "rigel";
    platforms = [ "x86_64-linux" ];
    sourceProvenance = with sourceTypes; [ binaryNativeCode ];
  };
}
