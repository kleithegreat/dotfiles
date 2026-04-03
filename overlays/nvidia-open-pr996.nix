# Temporary desktop-only workaround for NVIDIA open-gpu-kernel-modules PR #996.
# Remove once a future NVIDIA driver release includes the resume-side reset.
final: prev:
let
  pr996Patch = ../patches/nvidia/nvidia-open-pr996.patch;
in
{
  linuxPackages = prev.linuxPackages.extend (
    lfinal: lprev: {
      nvidiaPackages = lprev.nvidiaPackages.extend (
        nfinal: nprev:
        let
          production = nprev.production;
        in
        {
          # `nvidia-open` is built from `passthru.open`, so patch the driver via
          # `mkDriver` and `patchesOpen` instead of trying to override the outer drv.
          production = nprev.mkDriver {
            version = production.version;
            sha256_64bit = production.src.outputHash;
            openSha256 = production.open.src.outputHash;
            settingsSha256 = production.settings.src.outputHash;
            settingsVersion = production.settingsVersion;
            persistencedSha256 = production.persistenced.src.outputHash;
            persistencedVersion = production.persistencedVersion;
            patchesOpen = [ pr996Patch ];
          };

          stable =
            if prev.stdenv.hostPlatform.system == "i686-linux" then
              nprev.legacy_390
            else
              nfinal.production;
        }
      );

      nvidia_x11 = lfinal.nvidiaPackages.stable;
      nvidia_x11_production = lfinal.nvidiaPackages.production;
      nvidia_x11_stable_open = lfinal.nvidiaPackages.stable.open;
      nvidia_x11_production_open = lfinal.nvidiaPackages.production.open;
    }
  );
}
