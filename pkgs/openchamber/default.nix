{
  lib,
  buildNpmPackage,
  fetchNpmDeps,
  fetchurl,
  pkg-config,
  python3,
}:

let
  pname = "openchamber";
  version = "1.9.6";
  src = fetchurl {
    url = "https://registry.npmjs.org/@openchamber/web/-/web-${version}.tgz";
    hash = "sha512-vV9aAhSv/Y+Ms9/aTKVpku/9WLpv8x7wO3KdnnJayH5vQSijeIiXfMoUEGww3I7b90oM5SrXPAzPy4uhlGq3aQ==";
  };
  postPatch = ''
    cp ${./package.json} package.json
    cp ${./package-lock.json} package-lock.json
  '';
in
buildNpmPackage {
  inherit pname version src postPatch;

  npmDeps = fetchNpmDeps {
    name = "${pname}-${version}-npm-deps";
    inherit src postPatch;
    hash = "sha256-hk+rmUYbuq8OsW4km9lepVslVHI3CCmGM/k7+/+EnjE=";
  };

  nativeBuildInputs = [
    pkg-config
    python3
  ];

  # The published npm package already ships its built dist/ assets.
  dontNpmBuild = true;

  meta = with lib; {
    description = "Browser UI and remote interface for OpenCode";
    homepage = "https://github.com/openchamber/openchamber";
    license = licenses.mit;
    mainProgram = "openchamber";
    platforms = platforms.linux;
  };
}
