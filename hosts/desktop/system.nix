{ config, pkgs, lib, ... }:

{
  imports = [
    ./macos-vm.nix
  ];

  boot.initrd.availableKernelModules = [ "xhci_pci" "ahci" "nvme" "usbhid" "usb_storage" "sd_mod" ];
  boot.kernelPatches = [
    {
      name = "desktop-preempt-full-kernel-config";
      patch = null;
      structuredExtraConfig = with lib.kernel; {
        PREEMPT_DYNAMIC = lib.mkForce no;
        PREEMPT = lib.mkForce yes;
        PREEMPT_LAZY = lib.mkForce no;
        PREEMPT_VOLUNTARY = lib.mkForce no;

        # Trim desktop-only dead weight while keeping the active NVIDIA, Intel
        # Wi-Fi, USB audio, webcam, and KVM host paths intact.
        KVM_AMD = lib.mkForce no;
        X86_AMD_PLATFORM_DEVICE = lib.mkForce no;
        AMD_MEM_ENCRYPT = lib.mkForce no;
        AMD_PMC = lib.mkForce no;
        AMD_IOMMU = lib.mkForce no;

        XEN = lib.mkForce no;
        HYPERV = lib.mkForce no;
        KVM_GUEST = lib.mkForce no;
        NET_9P = lib.mkForce no;

        DRM_NOUVEAU = lib.mkForce no;

        ATA_PIIX = lib.mkForce no;
        PATA_MARVELL = lib.mkForce no;
        SATA_SIS = lib.mkForce no;
        SATA_ULI = lib.mkForce no;
        SATA_VIA = lib.mkForce no;

        USB_EHCI_HCD = lib.mkForce no;
        USB_OHCI_HCD = lib.mkForce no;
        USB_UHCI_HCD = lib.mkForce no;

        BTRFS_FS = lib.mkForce no;
        XFS_FS = lib.mkForce no;
        SMB_SERVER = lib.mkForce no;
        SQUASHFS = lib.mkForce no;
      };
    }
  ];
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

  virtualisation.macosVm.enable = true;

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
    powerManagement.kernelSuspendNotifier = false; # Experiment: try legacy sleep units after GSP heartbeat timeout on resume.
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
    protontricks.enable = true;
  };

  environment.systemPackages = with pkgs; [
    nvidia-vaapi-driver  # VA-API backend for NVIDIA (LIBVA_DRIVER_NAME=nvidia)
  ];
}
