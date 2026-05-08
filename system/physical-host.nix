{ config, lib, pkgs, host, enableNativeOptimizations }:

let
  optimizedKernelPackages = import ./native-kernel-packages.nix {
    inherit lib pkgs host enableNativeOptimizations;
  };
  kernelOomNotifier = pkgs.writeShellApplication {
    name = "kernel-oom-notifier";
    runtimeInputs = with pkgs; [ coreutils libnotify systemd util-linux ];
    text = ''
      notify_user=kevin
      notify_uid="$(id -u "$notify_user")"

      journalctl --dmesg --follow --output=cat --since=now | while IFS= read -r line; do
        summary=""

        case "$line" in
          *"Killed process "*)
            rest="''${line#*Killed process }"
            pid="''${rest%% *}"
            comm="process"

            case "$rest" in
              *"("*")"*)
                comm="''${rest#*(}"
                comm="''${comm%%)*}"
                ;;
            esac

            summary="Kernel OOM killed $comm"
            if [ -n "$pid" ]; then
              summary="$summary (pid $pid)"
            fi
            ;;
          *"Out of memory:"*)
            summary="Kernel OOM event"
            ;;
          *)
            continue
            ;;
        esac

        if [ -S "/run/user/$notify_uid/bus" ]; then
          runuser -u "$notify_user" -- env \
            XDG_RUNTIME_DIR="/run/user/$notify_uid" \
            DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$notify_uid/bus" \
            notify-send \
              --app-name="kernel-oom" \
              --urgency=critical \
              --expire-time=15000 \
              "$summary" \
              "$line" || true
        fi
      done
    '';
  };
in
{
  config = lib.mkIf host.isPhysical {
    boot.kernelPackages = optimizedKernelPackages;
    boot.kernelParams = [ "mitigations=off" "transparent_hugepage=madvise" ];
    boot.kernelModules = [ "kvm-intel" "iptable_nat" ];
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

    systemd.services.kernel-oom-notifier = {
      description = "Notify the desktop session about kernel OOM kills";
      wantedBy = [ "multi-user.target" ];
      after = [ "systemd-journald.service" ];
      serviceConfig = {
        ExecStart = "${kernelOomNotifier}/bin/kernel-oom-notifier";
        Restart = "always";
        RestartSec = "2s";
      };
    };

    nix.settings.max-jobs = 2;
    networking.useDHCP = lib.mkDefault true;
    zramSwap = {
      enable = true;
      memoryPercent = 50;
    };

    hardware.enableRedistributableFirmware = true;
    hardware.i2c.enable = true;
    hardware.cpu.intel.updateMicrocode =
      lib.mkDefault config.hardware.enableRedistributableFirmware;

    # Bound rare upstream tailscaled shutdown hangs so reboot does not wait for
    # the full systemd default stop timeout.
    systemd.services.tailscaled.serviceConfig.TimeoutStopSec = "15s";
  };
}
