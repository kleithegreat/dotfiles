{ config, lib, pkgs, host, enableNativeOptimizations }:

let
  optimizedKernelPackages = import ./native-kernel-packages.nix {
    inherit lib pkgs host enableNativeOptimizations;
  };
in
{
  config = lib.mkIf host.isPhysical {
    boot.kernelPackages = optimizedKernelPackages;
    boot.kernelParams = [ "mitigations=off" "transparent_hugepage=madvise" ];
    boot.kernelModules = [ "kvm-intel" ];
    virtualisation.windowsVm.enable = true;
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
    boot.kernel.sysctl = {
      "kernel.sched_autogroup_enabled" = 1;
      "net.core.default_qdisc" = "fq";
      "net.ipv4.tcp_congestion_control" = "bbr";
    };

    systemd.services.mglru-tuning = {
      description = "Apply physical-host MGLRU tuning";
      wantedBy = [ "multi-user.target" ];
      after = [ "local-fs.target" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        # Use MGLRU's thrash-prevention knob as the MGLRU-friendly equivalent of
        # LE9/LE10-style working-set and file-cache protection.
        if [ -w /sys/kernel/mm/lru_gen/enabled ]; then
          printf 'y' > /sys/kernel/mm/lru_gen/enabled
        fi

        if [ -w /sys/kernel/mm/lru_gen/min_ttl_ms ]; then
          printf '1000' > /sys/kernel/mm/lru_gen/min_ttl_ms
        fi
      '';
    };

    nix.settings.max-jobs = 1;
    networking.useDHCP = lib.mkDefault true;
    zramSwap = {
      enable = true;
      memoryPercent = 50;
    };

    hardware.enableRedistributableFirmware = true;
    hardware.cpu.intel.updateMicrocode =
      lib.mkDefault config.hardware.enableRedistributableFirmware;

    # Bound rare upstream tailscaled shutdown hangs so reboot does not wait for
    # the full systemd default stop timeout.
    systemd.services.tailscaled.serviceConfig.TimeoutStopSec = "15s";
  };
}
