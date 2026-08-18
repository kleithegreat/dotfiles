{ self }:
let
  inherit (self.lists) filter unique;
  inherit (self.strings) concatStringsSep;
in
{
  # Host-native codegen flags, applied per package rather than package-set wide.
  # Anything built through these loses binary cache hits -- the extra flags
  # change its store path -- so each optimized derivation also carries a
  # host-specific `requiredSystemFeatures` tag, which stops desktop and laptop
  # from substituting each other's native outputs.
  optimize.forHost =
    host:
    let
      enabled = host.nativeOptimizations;
      hostFeature = "native-optimized-${host.name}";

      joinFlags = flags: flags |> filter (flag: flag != null && flag != "") |> concatStringsSep " ";

      # Flags already on the derivation live in `env` on a structured-attrs
      # build and at the top level otherwise; preserve whichever is present.
      existingFlags =
        old: name:
        if (old.env or { }) ? ${name} then
          toString old.env.${name}
        else if old ? ${name} then
          toString old.${name}
        else
          null;

      optimizer =
        name: flags: drv:
        if !enabled then
          drv
        else
          drv.overrideAttrs (old: {
            requiredSystemFeatures = unique ((old.requiredSystemFeatures or [ ]) ++ [ hostFeature ]);
            env = (old.env or { }) // {
              ${name} = joinFlags [
                (existingFlags old name)
                (joinFlags flags)
              ];
            };
          });
    in
    {
      inherit enabled hostFeature;

      cc = optimizer "NIX_CFLAGS_COMPILE" [
        "-O3"
        "-march=native"
      ];

      rust = optimizer "RUSTFLAGS" [
        "-C"
        "target-cpu=native"
      ];
    };
}
