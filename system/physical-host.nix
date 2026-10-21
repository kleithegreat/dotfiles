{ config, lib, pkgs, host, ... }:

{
  config = lib.mkIf host.isPhysical {
    boot.kernelParams = [
      "vt.global_cursor_default=0"
      "mitigations=off"
      "transparent_hugepage=madvise"
    ];
    # SDDM shows its greeter's VT for a moment when it hands off to the
    # session: wipe the boot log off VT 1 before the greeter takes it.
    systemd.services.display-manager.serviceConfig = {
      TTYPath = "/dev/tty1";
      TTYVTDisallocate = true;
    };
    boot.kernelModules = [
      "kvm-intel"
      "ntsync" # ableton-wine's Wine requires /dev/ntsync
      # The sysctls below would autoload these behind every pending driver probe.
      "tcp_bbr"
      "sch_fq"
    ];
    boot.loader.grub = {
      enable = true;
      efiSupport = true;
      device = "nodev";
      useOSProber = false; # other EFI installs are chainloaded explicitly below, never discovered
      extraEntries = ''
        menuentry "Windows Boot Manager" {
          search --set=root --file /EFI/Microsoft/Boot/bootmgfw.efi
          chainloader /EFI/Microsoft/Boot/bootmgfw.efi
        }
        menuentry "UEFI Firmware Settings" {
          fwsetup
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
      # zram-only swap: swapping is cheaper than dropping page cache.
      "vm.swappiness" = 180;
    };

    systemd.services.mglru-tuning = {
      description = "Apply physical-host MGLRU tuning";
      wantedBy = [ "multi-user.target" ];
      after = [ "local-fs.target" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = /* bash */ ''
        if [ -w /sys/kernel/mm/lru_gen/enabled ]; then
          printf 'y' > /sys/kernel/mm/lru_gen/enabled
        fi

        if [ -w /sys/kernel/mm/lru_gen/min_ttl_ms ]; then
          printf '1000' > /sys/kernel/mm/lru_gen/min_ttl_ms
        fi
      '';
    };

    systemd.services.kernel-oom-notifier = {
      description = "Notify the desktop session about kernel OOM kills";
      wantedBy = [ "multi-user.target" ];
      after = [ "systemd-journald.service" ];
      serviceConfig = {
        ExecStart = lib.getExe pkgs.kernel-oom-notifier;
        Restart = "always";
        RestartSec = "2s";
      };
    };

    nix.settings.max-jobs = 2;

    # On the tmpfs /tmp, large CUDA build trees OOM the machine. No age on the
    # rule: survivors are `--keep-failed` trees somebody wants to inspect.
    systemd.services.nix-daemon.environment.TMPDIR = "/var/tmp/nix-daemon";
    systemd.tmpfiles.rules = [ "d /var/tmp/nix-daemon 0755 root root -" ];

    networking.useDHCP = lib.mkDefault true;
    zramSwap = {
      enable = true;
      memoryPercent = 100;
    };

    hardware.enableRedistributableFirmware = true;
    hardware.i2c.enable = true;
    # The tray process is owned by Hyprland autostart, not `userService`.
    programs.solaar.enable = true;
    hardware.cpu.intel.updateMicrocode =
      lib.mkDefault config.hardware.enableRedistributableFirmware;

    # What Mission Center's inert "Run Additional Setup" would install; see docs/nix.md.
    security.wrappers.nethogs = {
      owner = "root";
      group = "root";
      capabilities = "cap_net_admin,cap_net_raw,cap_dac_read_search,cap_sys_ptrace+ep";
      source = lib.getExe pkgs.nethogs;
    };

    # Re-opens energy_uj, which the kernel closed against PLATYPUS.
    services.udev.extraRules = ''
      SUBSYSTEM=="powercap", KERNEL=="intel-rapl*", RUN+="${lib.getExe' pkgs.coreutils "chmod"} a+r /sys%p/energy_uj"
    '';

    # wgengine teardown races can otherwise eat most of the 90s stop timeout.
    systemd.services.tailscaled.serviceConfig.TimeoutStopSec = "15s";

    services.power-profiles-daemon.enable = true;

    programs.steam = {
      enable = true;
      remotePlay.openFirewall = true;
      localNetworkGameTransfers.openFirewall = true;
      extest.enable = true;
    };
  };
}
