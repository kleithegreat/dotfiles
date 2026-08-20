{ pkgs, lib, ... }:

{
  # ── Dell SMM userspace fan control ──────────────────────────
  #
  # dell-smm-hwmon autoloads on XPS models via the pn*XPS* DMI alias, and the
  # dell-bios-fan-control module below also lists its "i8k" modalias;
  # declaring it here makes the dependency explicit.
  boot.kernelModules = [ "dell-smm-hwmon" ];

  # Disable BIOS fan management so i8kmon can set speeds directly.
  # Runs `dell-bios-fan-control 0` at boot and restores on stop/suspend.
  services.hardware.dell-bios-fan-control.enable = true;

  # Tag the dell_smm hwmon device so systemd can bind i8kmon to it.
  services.udev.extraRules = ''
    SUBSYSTEM=="hwmon", ATTRS{name}=="dell_smm", TAG+="systemd", ENV{SYSTEMD_ALIAS}="/sys/subsystem/hwmon/devices/dell_smm"
  '';

  # ── i8kmon configuration ────────────────────────────────────
  # More aggressive profile for XPS 15 9520 (Alder Lake + RTX 3050 Mobile).
  # The Dell SMM interface still only exposes the firmware fan states, so the
  # best we can do is ramp into state 2 sooner and poll more frequently.
  #
  # Fan speeds: 0 = off, 1 = low (~2500 RPM), 2 = high (~4500 RPM)
  # Fields: {left right} temp_down_ac temp_up_ac temp_down_batt temp_up_batt
  environment.etc."i8kmon.conf".text = ''
    set config(verbose) 0
    set config(timeout) 2
    set config(num_configs) 4

    set config(0) {{0 0}  -1  50  -1  50}
    set config(1) {{1 1}  40  60  40  60}
    set config(2) {{1 2}  50  68  50  68}
    set config(3) {{2 2}  58 128  58 128}
  '';

  # ── i8kmon systemd service ──────────────────────────────────
  systemd.services.i8kmon = {
    description = "Dell laptop fan control (i8kmon)";
    after = [
      "sys-subsystem-hwmon-devices-dell_smm.device"
      "multi-user.target"
    ];
    bindsTo = [ "sys-subsystem-hwmon-devices-dell_smm.device" ];
    requisite = [ "multi-user.target" ];
    wantedBy = [ "sys-subsystem-hwmon-devices-dell_smm.device" ];
    serviceConfig = {
      ExecStart = lib.getExe pkgs.i8kutils;
      Restart = "on-failure";
      RestartSec = 5;
    };
  };

  environment.systemPackages = [ pkgs.i8kutils ];
}
