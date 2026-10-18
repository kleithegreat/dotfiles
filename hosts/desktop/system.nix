{ config, lib, pkgs, ... }:

{
  boot.initrd.availableKernelModules = [ "xhci_pci" "ahci" "nvme" "usbhid" "usb_storage" "sd_mod" ];
  boot.kernel.sysctl = {
    "vm.dirty_ratio" = 10;
    "vm.dirty_background_ratio" = 5;
  };
  # Preserved VRAM must survive suspend, and /tmp is tmpfs; without it resumes garble.
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
    options = [ "fmask=0077" "dmask=0077" "noauto" "x-systemd.automount" ];
  };

  fileSystems."/mnt/shared" = {
    device = "/dev/disk/by-uuid/426244fd-2b88-4eae-81fe-3466fc631d43";
    fsType = "ext4";
    options = [ "nofail" "x-systemd.device-timeout=10s" ];
  };

  systemd.services.power-profiles-daemon.postStart = /* bash */ ''
    ${lib.getExe' config.services.power-profiles-daemon.package "powerprofilesctl"} set performance
  '';

  hardware.graphics.enable = true;
  hardware.nvidia = {
    modesetting.enable = true;
    open = true;
    powerManagement.enable = true;
    # Held until the resume validation in TODO.md passes.
    powerManagement.kernelSuspendNotifier = false;
  };
  services.xserver.videoDrivers = [ "nvidia" ];

  # Freezing user sessions on suspend black-screens resume (nixpkgs #371058).
  systemd.services.systemd-suspend.environment.SYSTEMD_SLEEP_FREEZE_USER_SESSIONS = "false";

  environment.sessionVariables.__EGL_VENDOR_LIBRARY_FILENAMES =
    "/run/opengl-driver/share/glvnd/egl_vendor.d/10_nvidia.json:/run/opengl-driver/share/glvnd/egl_vendor.d/50_mesa.json";

  # ── GPU fans ──────────────────────────────────────────────────
  services.lact.enable = true;
  # Not `services.lact.settings`: lactd needs integer curve keys, which it can only emit as strings.
  environment.etc."lact/config.yaml".text = /* yaml */ ''
    version: 7
    daemon:
      log_level: info
      admin_group: wheel
    gpus:
      10DE:2206-10DE:1467-0000:01:00.0:
        fan_control_enabled: true
        fan_control_settings:
          mode: curve
          static_speed: 1.0
          temperature_key: GPU
          interval_ms: 500
          curve:
            50: 0.40
            60: 0.55
            70: 0.75
            78: 1.0
          spindown_delay_ms: 5000
          change_threshold: 2
          # Manual mode can't stop the fans; below this the vBIOS's zero-RPM idle takes over.
          auto_threshold: 45
  '';
  systemd.services.lactd.restartTriggers = [ config.environment.etc."lact/config.yaml".source ];

  # ── Location ──────────────────────────────────────────────────
  # Stationary: pinned, not geolocated (docs/sun-schedule.md). Ithaca, NY.
  time.timeZone = "America/New_York";
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
  # Covers gaps in Folding@home's GPU work, yielding once a GPU core runs.
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

  environment.systemPackages = [ pkgs.macos-vm ];
}
