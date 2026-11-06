{ self }:
let
  inherit (self.lists) filter unique;
  inherit (self.strings) concatStringsSep;
in
{
  # Per package, never set-wide; the feature tag stops hosts sharing native outputs.
  optimize.forHost =
    host:
    let
      enabled = host.nativeOptimizations;
      hostFeature = "native-optimized-${host.name}";

      joinFlags = flags: flags |> filter (flag: flag != null && flag != "") |> concatStringsSep " ";

      # Existing flags live in `env` under structured attrs, top level otherwise.
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
