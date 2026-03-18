{ config, pkgs, lib, ... }:

{
  # Hardware — from nixos-generate-config
  boot.initrd.availableKernelModules = [ "xhci_pci" "thunderbolt" "vmd" "nvme" "rtsx_pci_sdmmc" ];
  boot.kernelModules = [ "kvm-intel" ];

  fileSystems."/" = {
    device = "/dev/disk/by-uuid/b570af09-b288-4994-8373-f87cbe7ec964";
    fsType = "ext4";
  };

  fileSystems."/boot/efi" = {
    device = "/dev/disk/by-uuid/D85B-8832";
    fsType = "vfat";
    options = [ "fmask=0077" "dmask=0077" ];
  };

  swapDevices = [{ device = "/swapfile"; size = 16384; }];

  hardware.enableRedistributableFirmware = true;
  hardware.cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;

  # Boot — GRUB with EFI and OS prober (for Arch + Windows dual-boot)
  boot.loader.grub = {
    enable = true;
    efiSupport = true;
    device = "nodev";
    useOSProber = false;
    extraEntries = ''
      menuentry "Arch Linux" {
        search --set=root --file /EFI/Arch/grubx64.efi
        chainloader /EFI/Arch/grubx64.efi
      }
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

  # NVIDIA hybrid graphics (Intel Iris Xe + RTX 3050 Mobile)
  hardware.graphics.enable = true;
  hardware.nvidia = {
    modesetting.enable = true;
    open = true;
    powerManagement.enable = true;
    powerManagement.finegrained = true;
    prime = {
      offload = {
        enable = true;
        enableOffloadCmd = true;
      };
      intelBusId = "PCI:0:2:0";
      nvidiaBusId = "PCI:1:0:0";
    };
  };
  services.xserver.videoDrivers = [ "modesetting" "nvidia" ];

  # Laptop overrides — disable services enabled in shared configuration.nix
  hardware.bluetooth.powerOnBoot = lib.mkForce false;
  services.samba.enable = lib.mkForce false;
  services.openssh.enable = lib.mkForce false;

  services.power-profiles-daemon.enable = true;

  # Runs `powertop --auto-tune` at boot to enable runtime PM on devices that
  # don't default to it (NVMe, audio codec, sensor hub, etc.)
  powerManagement.powertop.enable = true;
  networking.useDHCP = lib.mkDefault true;

  environment.systemPackages = with pkgs; [ ];
}
