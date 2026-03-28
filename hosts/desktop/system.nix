{ config, pkgs, lib, ... }:

{
  boot.initrd.availableKernelModules = [ "xhci_pci" "ahci" "nvme" "usbhid" "usb_storage" "sd_mod" ];
  boot.kernelModules = [ "kvm-intel" ];

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

  swapDevices = [{ device = "/swapfile"; size = 16384; }];

  hardware.enableRedistributableFirmware = true;
  hardware.cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;

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
  };
  services.xserver.videoDrivers = [ "nvidia" ];

  networking.useDHCP = lib.mkDefault true;

  environment.systemPackages = with pkgs; [ ];
}