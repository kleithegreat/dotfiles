{ config, pkgs, lib, ... }:

let
  # The firmware exposes three fan states and dell-smm-hwmon quantises pwm onto
  # them: 0 / 128 / 255 = off / low / high. There is nothing between low and
  # high, and fan*_target is read-only, so a "curve" can only ever be this
  # three-step staircase driven from userspace -- the kernel registers the fans
  # as cooling devices (dell-smm-fan1/2) but no thermal zone binds them, and a
  # binding cannot be created from sysfs.
  #
  # pwm*_enable=1 is manual mode and issues the same SMM call as
  # `dell-bios-fan-control 0`; =2 hands the fans back to the EC.
  curve = pkgs.writeShellApplication {
    name = "dell-fan-curve";
    runtimeInputs = [ pkgs.coreutils ];
    text = ''
      smm=; core=
      for hwmon in /sys/class/hwmon/hwmon*; do
        case "$(cat "$hwmon/name" 2>/dev/null)" in
          dell_smm) smm=$hwmon ;;
          coretemp) core=$hwmon ;;
        esac
      done
      if [ -z "$smm" ] || [ -z "$core" ]; then
        echo "dell_smm or coretemp hwmon device not found" >&2
        exit 1
      fi

      echo 1 > "$smm/pwm1_enable"
      echo 1 > "$smm/pwm2_enable"

      state=-1
      while :; do
        temp=$(( $(cat "$core/temp1_input") / 1000 ))

        # Hysteresis bands: the step down is 10C below the step up, so the fans
        # settle instead of chattering across a threshold under bursty load.
        case "$state" in
          2) if [ "$temp" -lt 70 ]; then next=1; else next=2; fi ;;
          1) if [ "$temp" -ge 80 ]; then next=2
             elif [ "$temp" -lt 45 ]; then next=0
             else next=1; fi ;;
          *) if [ "$temp" -ge 80 ]; then next=2
             elif [ "$temp" -ge 55 ]; then next=1
             else next=0; fi ;;
        esac

        if [ "$next" != "$state" ]; then
          case "$next" in
            0) pwm=0 ;;
            1) pwm=128 ;;
            2) pwm=255 ;;
          esac
          # Re-assert manual mode on every change: the EC reclaims the fans
          # across suspend, and a pwm written while it owns them is dropped.
          echo 1 > "$smm/pwm1_enable"
          echo 1 > "$smm/pwm2_enable"
          echo "$pwm" > "$smm/pwm1"
          echo "$pwm" > "$smm/pwm2"
          state=$next
        fi

        sleep 2
      done
    '';
  };

  # Safety net: if the daemon ever stops with the fans parked at a low state,
  # nothing else would spin them back up, so hand control back to the EC.
  restoreAuto = pkgs.writeShellApplication {
    name = "dell-fan-restore-auto";
    runtimeInputs = [ pkgs.coreutils ];
    text = ''
      for hwmon in /sys/class/hwmon/hwmon*; do
        if [ "$(cat "$hwmon/name" 2>/dev/null)" = dell_smm ]; then
          echo 2 > "$hwmon/pwm1_enable"
          echo 2 > "$hwmon/pwm2_enable"
        fi
      done
    '';
  };
in
{
  boot.kernelModules = [ "dell-smm-hwmon" ];

  # The hwmonN index is not stable across boots, so bind by device name instead.
  services.udev.extraRules = ''
    SUBSYSTEM=="hwmon", ATTRS{name}=="dell_smm", TAG+="systemd", ENV{SYSTEMD_ALIAS}="/sys/subsystem/hwmon/devices/dell_smm"
  '';

  systemd.services.dell-fan-curve = {
    description = "Three-step Dell fan curve on CPU package temperature";
    bindsTo = [ "sys-subsystem-hwmon-devices-dell_smm.device" ];
    after = [ "sys-subsystem-hwmon-devices-dell_smm.device" ];
    wantedBy = [ "sys-subsystem-hwmon-devices-dell_smm.device" ];
    serviceConfig = {
      ExecStart = lib.getExe curve;
      ExecStopPost = lib.getExe restoreAuto;
      Restart = "on-failure";
      RestartSec = 5;
    };
  };

  systemd.services.dell-fan-curve-resume = {
    description = "Restart the Dell fan curve after resume";
    wantedBy = [ "suspend.target" ];
    after = [ "suspend.target" ];
    serviceConfig = {
      Type = "oneshot";
      # The EC reclaims the fans across suspend and swallows writes until it has
      # settled; nixpkgs' dell-bios-fan-control-resume waits out the same 30s.
      ExecStartPre = "${pkgs.coreutils}/bin/sleep 30";
      ExecStart = "${config.systemd.package}/bin/systemctl restart dell-fan-curve.service";
    };
  };
}
