{ lib, buildNpmPackage }:

buildNpmPackage {
  pname = "unearth-vicinae";
  version = "0.1.0";

  src = lib.fileset.toSource {
    root = ./.;
    fileset = lib.fileset.unions [
      ./package.json
      ./package-lock.json
      ./src
      ./assets
    ];
  };
  npmDepsHash = "sha256-yEpyieO2OQLeGYSB6PgkqGdyHHBiuL+9A4TGQyk+OYc=";

  # `vici build` stages beside its output directory, which must not be the store.
  buildPhase = /* bash */ ''
    runHook preBuild
    npm run build -- --out "$PWD/dist"
    runHook postBuild
  '';

  installPhase = /* bash */ ''
    runHook preInstall
    cp --recursive dist "$out"
    runHook postInstall
  '';
}
