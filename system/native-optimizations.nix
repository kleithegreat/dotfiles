{ lib, host, enableNativeOptimizations ? false }:

let
  enabled = enableNativeOptimizations;
  hostFeature = if enabled then "native-optimized-${host.name}" else null;

  cFlags = lib.optionals enabled [
    "-O3"
    "-march=native"
  ];

  rustFlags = lib.optionals enabled [
    "-C"
    "target-cpu=native"
  ];

  joinFlags =
    flags:
    lib.concatStringsSep " " (lib.filter (flag: flag != null && flag != "") flags);

  getExistingEnvValue =
    envName: oldEnv: old:
    if builtins.hasAttr envName oldEnv then
      toString (builtins.getAttr envName oldEnv)
    else if builtins.hasAttr envName old then
      toString (builtins.getAttr envName old)
    else
      null;

  nativeHostAttrs =
    old:
    lib.optionalAttrs enabled {
      requiredSystemFeatures = lib.unique ((old.requiredSystemFeatures or [ ]) ++ [ hostFeature ]);
    };

  mkOptimizedAttrs =
    {
      includeCFlags ? false,
      includeRustFlags ? false,
    }:
    old:
    let
      oldEnv = old.env or { };
      envOverrides =
        lib.optionalAttrs includeCFlags {
          NIX_CFLAGS_COMPILE = joinFlags [
            (getExistingEnvValue "NIX_CFLAGS_COMPILE" oldEnv old)
            (joinFlags cFlags)
          ];
        }
        // lib.optionalAttrs includeRustFlags {
          RUSTFLAGS = joinFlags [
            (getExistingEnvValue "RUSTFLAGS" oldEnv old)
            (joinFlags rustFlags)
          ];
        };
    in
    nativeHostAttrs old
    // lib.optionalAttrs enabled {
      env = oldEnv // envOverrides;
    };

  optimizePackage =
    opts: drv:
    if enabled then
      drv.overrideAttrs (mkOptimizedAttrs opts)
    else
      drv;
in
{
  inherit enabled hostFeature cFlags rustFlags joinFlags nativeHostAttrs optimizePackage;

  requireNativeBuildHost =
    drv:
    if enabled then
      drv.overrideAttrs nativeHostAttrs
    else
      drv;

  optimizeCCPackage = optimizePackage {
    includeCFlags = true;
  };

  optimizeRustPackage = optimizePackage {
    includeRustFlags = true;
  };

  optimizeNativePackage = optimizePackage {
    includeCFlags = true;
    includeRustFlags = true;
  };
}
