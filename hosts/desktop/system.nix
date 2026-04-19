{ config, pkgs, lib, hostName, enableNativeOptimizations, ... }:

let
  optimizedKernelPackages = import ../../system/native-kernel-packages.nix {
    inherit lib pkgs hostName enableNativeOptimizations;
  };
in

{
  imports = [
    ./wine-ableton.nix
    ./windows-vm.nix
  ];

  nixpkgs.overlays = [
    # Temporary desktop-only NVIDIA open-kernel workaround for PR #996.
    # Remove once a future driver release includes the resume-side reset.
    (import ../../overlays/nvidia-open-pr996.nix)
  ];

  boot.initrd.availableKernelModules = [ "xhci_pci" "ahci" "nvme" "usbhid" "usb_storage" "sd_mod" ];
  # Keep the stock kernel version/package set, but compile it for this host CPU.
  boot.kernelPackages = optimizedKernelPackages;
  # Disable the kernel's CPU side-channel mitigation set on this bare-metal host.
  boot.kernelParams = [ "mitigations=off" ];
  boot.kernelModules = [ "kvm-intel" ];
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

  zramSwap.enable = true;
  zramSwap.memoryPercent = 50;

  hardware.enableRedistributableFirmware = true;
  hardware.cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;

  # Large local builds already saturate this desktop internally, so serialize
  # derivations and let each one keep full core parallelism.
  nix.settings.max-jobs = 1;

  boot.loader.grub = {
    enable = true;
    efiSupport = true;
    device = "nodev";
    useOSProber = false;
    extraEntries = ''
      menuentry "Windows Boot Manager" {
        search --set=root --file /EFI/Microsoft/Boot/bootmgfw.efi
        chainloader /EFI/Microsoft/Boot/bootmgfw.efi
      }
    '';
  };
  boot.loader.efi = {
    canTouchEfiVariables = true;
    efiSysMountPoint = "/boot/efi";
  };

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

  networking.useDHCP = lib.mkDefault true;
  # Bound rare upstream tailscaled shutdown hangs so reboot does not wait for
  # the full systemd default stop timeout.
  systemd.services.tailscaled.serviceConfig.TimeoutStopSec = "15s";

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

  virtualisation.windowsVm.enable = true;
}
