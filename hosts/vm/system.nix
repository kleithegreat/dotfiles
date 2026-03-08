{ config, pkgs, lib, modulesPath, ... }:

{
  imports = [ (modulesPath + "/profiles/qemu-guest.nix") ];

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  fileSystems."/" = { device = "/dev/disk/by-label/nixos"; fsType = "ext4"; };
  fileSystems."/boot" = {
    device = "/dev/disk/by-label/BOOT";
    fsType = "vfat";
    options = [ "fmask=0077" "dmask=0077" ];
  };

  boot.initrd.availableKernelModules = [
    "ahci" "xhci_pci" "virtio_pci" "virtio_scsi"
    "virtio_blk" "virtio_net" "sd_mod" "sr_mod"
  ];
}
