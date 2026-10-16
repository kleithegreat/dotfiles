{ config, pkgs, lib, ... }:

{
  boot.initrd.availableKernelModules = [ "xhci_pci" "thunderbolt" "vmd" "nvme" "rtsx_pci_sdmmc" ];
  programs.ccache.enable = true;
  # Its stats helper wraps a Perl script, which security.wrappers now refuses.
  security.wrappers.nix-ccache.enable = false;
  nix.settings.extra-sandbox-paths = [ config.programs.ccache.cacheDir ];
  boot.kernelPackages = pkgs.linuxPackagesFor (pkgs.linuxPackages.kernel.override {
    stdenv = pkgs.ccacheStdenv.override {
      extraConfig = /* bash */ ''
        export CCACHE_DIR=${config.programs.ccache.cacheDir}
        export CCACHE_UMASK=007
        # Without the sandbox mount (first build, remote builder) compile uncached rather than fail.
        [ -w "$CCACHE_DIR" ] || export CCACHE_DISABLE=1
      '';
    };
  });
  boot.kernelPatches = [
    {
      name = "laptop-intel-only-kernel-config";
      patch = null;
      structuredExtraConfig = {
        PREEMPT_DYNAMIC = lib.mkForce lib.kernel.no;
        PREEMPT = lib.mkForce lib.kernel.no;
        PREEMPT_LAZY = lib.mkForce lib.kernel.no;
        PREEMPT_VOLUNTARY = lib.mkForce lib.kernel.yes;

        KVM_AMD = lib.mkForce lib.kernel.no;
        X86_AMD_PLATFORM_DEVICE = lib.mkForce lib.kernel.no;
        AMD_MEM_ENCRYPT = lib.mkForce lib.kernel.no;
        KVM_AMD_SEV = lib.mkForce lib.kernel.unset;
        SEV_GUEST = lib.mkForce lib.kernel.unset;
        AMD_PMC = lib.mkForce lib.kernel.no;
        AMD_IOMMU = lib.mkForce lib.kernel.no;

        XEN = lib.mkForce lib.kernel.no;
        HYPERV = lib.mkForce lib.kernel.no;
        DRM_HYPERV = lib.mkForce lib.kernel.unset;
        FB_HYPERV = lib.mkForce lib.kernel.unset;
        KVM_GUEST = lib.mkForce lib.kernel.no;

        DRM_NOUVEAU = lib.mkForce lib.kernel.no;
        DRM_NOUVEAU_SVM = lib.mkForce lib.kernel.unset;
      };
    }
  ];

  fileSystems."/" = {
    device = "/dev/disk/by-uuid/b570af09-b288-4994-8373-f87cbe7ec964";
    fsType = "ext4";
  };

  fileSystems."/boot/efi" = {
    device = "/dev/disk/by-uuid/D85B-8832";
    fsType = "vfat";
    options = [ "fmask=0077" "dmask=0077" "noauto" "x-systemd.automount" ];
  };

  hardware.graphics = {
    enable = true;
    # Backs LIBVA_DRIVER_NAME=iHD in env.lua; Mesa ships no iHD driver.
    extraPackages = [ pkgs.intel-media-driver ];
  };
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
  environment.sessionVariables.__EGL_VENDOR_LIBRARY_FILENAMES =
    "/run/opengl-driver/share/glvnd/egl_vendor.d/50_mesa.json";
  # GTK's Vulkan renderer wakes the dGPU on every launch; see docs/nvidia.md.
  environment.sessionVariables.GSK_RENDERER = "gl";
  # Restoring the keyboard backlight held sysinit.target for ~1.2s.
  systemd.units."systemd-backlight@leds:dell::kbd_backlight.service".enable = false;

  services.automatic-timezoned.enable = true;

  services.openssh.enable = lib.mkForce false;

  powerManagement.powertop.enable = true;

  # Touchpad runtime-PM pin (docs/nix.md) and colon-free GPU names (docs/nvidia.md).
  services.udev.extraRules = /* udev */ ''
    ACTION=="add|change", SUBSYSTEM=="pci", KERNEL=="0000:00:15.1", ATTR{power/control}="on"
    SUBSYSTEM=="drm", ENV{DEVTYPE}=="drm_minor", KERNEL=="card[0-9]*", SUBSYSTEMS=="pci", DRIVERS=="i915", SYMLINK+="dri/intel-gpu"
    SUBSYSTEM=="drm", ENV{DEVTYPE}=="drm_minor", KERNEL=="card[0-9]*", SUBSYSTEMS=="pci", DRIVERS=="nvidia", SYMLINK+="dri/nvidia-gpu"
  '';

  # Must hang off powertop.service itself; see docs/nix.md.
  systemd.services.powertop.serviceConfig.ExecStartPost =
    pkgs.writeShellScript "touchpad-i2c-pin-runtime-pm" /* bash */ ''
      echo on > /sys/bus/pci/devices/0000:00:15.1/power/control
    '';

  # ── Power profiles ──────────────────────────────────────────
  # Everything here follows power-profiles-daemon; see docs/laptop-power.md.
  services.scx = {
    enable = true;
    scheduler = "scx_lavd";
    extraArgs = [ "--autopower" ];
  };

  systemd.services.power-profile-follower = {
    description = "Apply the power-profile settings power-profiles-daemon does not own";
    wantedBy = [ "power-profiles-daemon.service" ];
    after = [ "power-profiles-daemon.service" ];
    partOf = [ "power-profiles-daemon.service" ];
    path = [ pkgs.glib config.services.power-profiles-daemon.package ];
    serviceConfig.Restart = "always";
    script = /* bash */ ''
      apply() {
        # 115 W is the firmware's own PL1. The MSR limit is left alone: the
        # lower of the two applies, so the MMIO one is enough to cap.
        case "$(powerprofilesctl get)" in
          power-saver) pl1=15000000 boost=0 ;;
          balanced) pl1=115000000 boost=0 ;;
          performance) pl1=115000000 boost=1 ;;
        esac
        echo "$pl1" > /sys/class/powercap/intel-rapl-mmio:0/constraint_0_power_limit_uw
        echo "$boost" > /sys/devices/system/cpu/intel_pstate/hwp_dynamic_boost
      }

      # Every line, the subscription's first included, re-applies idempotently.
      gdbus monitor --system \
        --dest org.freedesktop.UPower.PowerProfiles \
        --object-path /org/freedesktop/UPower/PowerProfiles |
        while read -r _; do apply; done
    '';
  };

  # Will not enumerate the ELAN touchpad, by design; see docs/nix.md.
  services.fwupd.enable = true;

  hardware.bluetooth = {
    enable = true;
    powerOnBoot = false;
  };

  # ── Fingerprint auth ────────────────────────────────────────
  # Goodix 27c6:63ac is in upstream libfprint; no TOD.
  services.fprintd = {
    enable = true;
    tod.enable = false;
  };

  security.pam.services = {
    # SDDM uses `login`; the greeter must always accept a password.
    login.fprintAuth = false;

    sudo.fprintAuth = true;
    polkit-1.fprintAuth = true;

    # hyprlock talks to fprintd natively; its PAM path stays password-only.
    hyprlock.fprintAuth = false;
  };

  # ── Polkit — local fingerprint management + Dell battery control ─
  # Otherwise every pkexec call fails "pkexec must be setuid root".
  security.polkit.enablePkexecWrapper = true;

  security.polkit.extraConfig = /* javascript */ ''
    polkit.addRule(function(action, subject) {
      // fprintd-delete names its user, which fprintd treats as setusername.
      if ((action.id === "net.reactivated.fprint.device.enroll" ||
           action.id === "net.reactivated.fprint.device.setusername") &&
          subject.user === "kevin" && subject.local && subject.active) {
        return polkit.Result.YES;
      }

      // Whole argument forms, never the program path: smbios-battery-ctl also
      // takes --password/--security-key.
      if (action.id === "org.freedesktop.policykit.exec" &&
          /\/smbios-battery-ctl$/.test(action.lookup("program")) &&
          /^\S*\/smbios-battery-ctl\s+(--get-charging-cfg|--set-charging-mode=(primarily_ac|adaptive|custom|standard|express)(\s+--set-custom-charge-interval\s+[0-9]+\s+[0-9]+)?)\s*$/.test(action.lookup("command_line")) &&
          subject.user === "kevin" && subject.local && subject.active) {
        return polkit.Result.YES;
      }
    });
  '';

  # ── Wi-Fi power management ──────────────────────────────────
  # iwlwifi powersave measured 30% loss and up to 1.2s RTT to the first hop on an idle link.
  networking.networkmanager.wifi.powersave = false;

  # ── Cornell eduroam ─────────────────────────────────────────
  networking.networkmanager.ensureProfiles = {
    environmentFiles = [ "/etc/nm-secrets/eduroam.env" ];
    profiles.eduroam = {
      connection = {
        id = "eduroam";
        type = "wifi";
      };
      wifi = {
        ssid = "eduroam";
        mode = "infrastructure";
      };
      wifi-security.key-mgmt = "wpa-eap";
      "802-1x" = {
        eap = "peap";
        phase2-auth = "mschapv2";
        anonymous-identity = "anonymous@cornell.edu"; # the NetID never goes out in the clear
        identity = "kl2344@cornell.edu";
        password = "$CORNELL_NETID_PASSWORD";
        password-flags = 0;
        # Never `system-ca-certs`: its OpenSSL ca_path needs c_rehash links NixOS doesn't ship.
        ca-cert = "/etc/ssl/certs/ca-certificates.crt";
        # Load-bearing: the server's public Sectigo chain alone would accept any bought cert.
        domain-suffix-match = "network-access.it.cornell.edu";
      };
      ipv4.method = "auto";
      ipv6.method = "auto";
    };
  };

  systemd.tmpfiles.rules = [ "d /etc/nm-secrets 0700 root root -" ];

  programs.captive-browser = {
    enable = true;
    interface = "wlp0s20f3";
  };

  environment.systemPackages = [ pkgs.libsmbios ];
}
