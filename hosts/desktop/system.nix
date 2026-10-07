{ config, lib, pkgs, ... }:

{
  boot.initrd.availableKernelModules = [ "xhci_pci" "ahci" "nvme" "usbhid" "usb_storage" "sd_mod" ];
  # Keep only the writeback tuning here; swappiness/vfs_cache_pressure stay at
  # kernel defaults, which suit the shared zram-only swap policy better than
  # the disk-swap-oriented values previously set.
  boot.kernel.sysctl = {
    "vm.dirty_ratio" = 10;
    "vm.dirty_background_ratio" = 5;
  };
  # Preserve VRAM across suspend/resume on this dedicated NVIDIA desktop.
  # /tmp is tmpfs-backed in shared config, so use disk-backed /var/tmp instead.
  boot.extraModprobeConfig = ''
    options nvidia NVreg_TemporaryFilePath=/var/tmp
  '';

  fileSystems."/" = {
    device = "/dev/disk/by-uuid/431cdfea-3583-453d-b2dd-9a46d01c4a33";
    fsType = "ext4";
  };

  fileSystems."/boot/efi" = {
    device = "/dev/disk/by-uuid/ECCF-6FDB";
    fsType = "vfat";
    options = [ "fmask=0077" "dmask=0077" ];
  };

  fileSystems."/mnt/shared" = {
    device = "/dev/disk/by-uuid/426244fd-2b88-4eae-81fe-3466fc631d43";
    fsType = "ext4";
    # Secondary data disk: never block boot on it.
    options = [ "nofail" "x-systemd.device-timeout=10s" ];
  };

  services.power-profiles-daemon.enable = true;
  # Keep this desktop pinned to the top performance profile whenever the daemon
  # comes up, including later restarts.
  systemd.services.power-profiles-daemon.postStart = /* bash */ ''
    ${config.services.power-profiles-daemon.package}/bin/powerprofilesctl set performance
  '';

  hardware.graphics.enable = true;
  hardware.nvidia = {
    modesetting.enable = true;
    open = true;
    powerManagement.enable = true;
    # Keep the legacy sleep-unit path while the no-overlay resume stack remains
    # unvalidated on the real desktop hardware.
    powerManagement.kernelSuspendNotifier = false;
  };
  services.xserver.videoDrivers = [ "nvidia" ];

  # Work around systemd 256+ failing to freeze user sessions on suspend,
  # which can cause a black screen on resume (nixpkgs #371058).
  systemd.services.systemd-suspend.environment.SYSTEMD_SLEEP_FREEZE_USER_SESSIONS = "false";

  # Load both the NVIDIA and Mesa EGL ICDs on this dedicated-GPU desktop.
  environment.sessionVariables.__EGL_VENDOR_LIBRARY_FILENAMES =
    "/run/opengl-driver/share/glvnd/egl_vendor.d/10_nvidia.json:/run/opengl-driver/share/glvnd/egl_vendor.d/50_mesa.json";

  # ── Locale ────────────────────────────────────────────────────
  # Stationary host: declare where it is rather than geolocating it. The zone
  # and the coordinates travel together — GeoClue resolves nothing real here
  # (see TODO.md), so sun-schedule would otherwise run on a stale fix from
  # wherever the cache was last written.
  time.timeZone = "America/New_York";
  # Ithaca, NY. Read by desktopctl's solar scheduler; outranks GeoClue and the
  # location cache.
  environment.sessionVariables.DESKTOPCTL_LOCATION = "42.4440,-76.5019";

  # ── Heater ────────────────────────────────────────────────────
  # Wanted by nothing: the shell's Power pane starts and stops it.
  systemd.user.services.heater = {
    description = "Folding@home as a space heater";
    serviceConfig = {
      ExecStart = lib.getExe pkgs.fahclient;
      StateDirectory = "heater";
      WorkingDirectory = "%S/heater";
      Restart = "on-failure";
    };
  };
  # Folding@home's servers do not always have GPU work, and the card is most of
  # the heat. This covers the gaps and yields as soon as a GPU core is running.
  systemd.user.services.heater-gpu-fallback = {
    description = "Burn the GPU while Folding@home has no work for it";
    partOf = [ "heater.service" ];
    wantedBy = [ "heater.service" ];
    serviceConfig = {
      ExecStart = lib.getExe (pkgs.writeShellApplication {
        name = "heater-gpu-fallback";
        runtimeInputs = [
          config.hardware.nvidia.package.bin
          pkgs.coreutils
          pkgs.gnugrep
          pkgs.gpu-burn
        ];
        text = /* bash */ ''
          while true; do
            if nvidia-smi --query-compute-apps=name --format=csv,noheader | grep --quiet FahCore; then
              sleep 30
            else
              # 1 GB already pins the card at full power. Without `-stts` every
              # burst is followed by 30 idle seconds of waiting on its workers.
              gpu_burn -stts 1 -m 1024 120 > /dev/null 2>&1
            fi
          done
        '';
      });
      Restart = "on-failure";
      RestartSec = 30;
    };
  };

  # ── Steam ─────────────────────────────────────────────────────
  programs.steam = {
    enable = true;
    remotePlay.openFirewall = true;
    localNetworkGameTransfers.openFirewall = true;
    extest.enable = true;  # X11→uinput translation for controllers on Wayland
  };
}
