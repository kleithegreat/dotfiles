{ config, pkgs, ... }:

{
  boot.initrd.availableKernelModules = [ "xhci_pci" "ahci" "nvme" "usbhid" "usb_storage" "sd_mod" ];
  boot.kernel.sysctl = {
    "vm.swappiness" = 10;
    "vm.dirty_ratio" = 10;
    "vm.dirty_background_ratio" = 5;
    "vm.vfs_cache_pressure" = 50;
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
  };

  services.power-profiles-daemon.enable = true;
  # Keep this desktop pinned to the top performance profile whenever the daemon
  # comes up, including later restarts.
  systemd.services.power-profiles-daemon.postStart = ''
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

  hardware.logitech.wireless = {
    enable = true;
    enableGraphical = true;  # solaar
  };

  # ── Steam ─────────────────────────────────────────────────────
  programs.steam = {
    enable = true;
    remotePlay.openFirewall = true;
    localNetworkGameTransfers.openFirewall = true;
    extest.enable = true;  # X11→uinput translation for controllers on Wayland
  };

  environment.systemPackages = with pkgs; [
    nvidia-vaapi-driver  # VA-API backend for NVIDIA (LIBVA_DRIVER_NAME=nvidia)
  ];
}
