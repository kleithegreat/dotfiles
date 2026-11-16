{ config, pkgs, lib, ... }:

let
  inherit (lib.attrsets) genAttrs;
  # Parents off, and the children nixpkgs sets under them unset (docs/nix.md).
  trim = { off, orphans ? [ ] }:
    genAttrs off (_: lib.mkForce lib.kernel.no) // genAttrs orphans (_: lib.mkForce lib.kernel.unset);
in
{
  boot.initrd.availableKernelModules = [ "xhci_pci" "thunderbolt" "vmd" "nvme" "rtsx_pci_sdmmc" ];
  boot.kernelPatches = [
    {
      # Other GPUs and server/VM display drivers; xe only autoloaded for its device ID.
      name = "laptop-trim-gpus";
      patch = null;
      structuredExtraConfig = trim {
        off = [
          "DRM_AMDGPU" "DRM_RADEON" "DRM_XE" "DRM_GMA500"
          "DRM_AST" "DRM_MGAG200" "DRM_QXL" "DRM_VBOXVIDEO" "DRM_VMWGFX"
          "DRM_CIRRUS_QEMU" "DRM_BOCHS" "DRM_VIRTIO_GPU"
        ];
        orphans = [
          "HSA_AMD" "HSA_AMD_P2P" "HMM_MIRROR"
          "DRM_AMD_ACP" "DRM_AMD_DC_DCN" "DRM_AMD_DC_FP" "DRM_AMD_DC_HDCP" "DRM_AMD_DC_SI"
          "DRM_AMD_ISP" "DRM_AMD_SECURE_DISPLAY" "DRM_AMDGPU_CIK" "DRM_AMDGPU_SI"
          "DRM_AMDGPU_USERPTR"
        ];
      };
    }
    {
      # TV tuners and PCI capture cards. UVC webcams are USB media, kept.
      name = "laptop-trim-tv-capture";
      patch = null;
      structuredExtraConfig = trim {
        off = [ "MEDIA_DIGITAL_TV_SUPPORT" "MEDIA_ANALOG_TV_SUPPORT" "MEDIA_PCI_SUPPORT" ];
        orphans = [ "MEDIA_ATTACH" "DVB_DYNAMIC_MINORS" ];
      } // {
        # Without the filter the TV switches are forced on.
        MEDIA_SUPPORT_FILTER = lib.mkForce lib.kernel.yes;
      };
    }
    {
      # NICs it lacks (USB Ethernet is not under ETHERNET); Intel, MediaTek, Realtek stay for the AX211 and Owly's USB card.
      name = "laptop-trim-network-chips";
      patch = null;
      structuredExtraConfig = trim {
        off = [
          "ETHERNET"
          "WLAN_VENDOR_ADMTEK" "WLAN_VENDOR_ATH" "WLAN_VENDOR_ATMEL" "WLAN_VENDOR_BROADCOM"
          "WLAN_VENDOR_INTERSIL" "WLAN_VENDOR_MARVELL" "WLAN_VENDOR_MICROCHIP"
          "WLAN_VENDOR_PURELIFI" "WLAN_VENDOR_QUANTENNA" "WLAN_VENDOR_RALINK"
          "WLAN_VENDOR_RSI" "WLAN_VENDOR_SILABS" "WLAN_VENDOR_ST" "WLAN_VENDOR_TI"
          "WLAN_VENDOR_ZYDAS"
        ];
        orphans = [
          "8139TOO_8129" "8139TOO_PIO" "MLX5_CORE_EN" "NET_VENDOR_MEDIATEK"
          "RT2800USB_RT53XX" "RT2800USB_RT55XX"
          "ATH9K_AHB" "ATH9K_PCI" "ATH9K_DFS_CERTIFIED" "ATH10K_DFS_CERTIFIED"
          "B43_PHY_HT" "BRCMFMAC_PCIE" "BRCMFMAC_USB"
        ];
      };
    }
    {
      # SCSI_LOWLEVEL is HBAs, RAID and FC cards; sd_mod, usb-storage and UAS sit outside it.
      name = "laptop-trim-server-hardware";
      patch = null;
      structuredExtraConfig = trim {
        off = [ "SCSI_LOWLEVEL" "INFINIBAND" "ISDN" "ATM" "CAN" "HAMRADIO" "STAGING" ];
        orphans = [
          "MEGARAID_NEWGEN" "SCSI_LOWLEVEL_PCMCIA" "SCSI_IBMVSCSI" "AIC7XXX_DEBUG_ENABLE"
          "AIC79XX_DEBUG_ENABLE" "AIC94XX_DEBUG" "INFINIBAND_IPOIB" "INFINIBAND_IPOIB_CM"
          "AX25" "STAGING_MEDIA"
        ];
      };
    }
    {
      # Cluster, network and historical filesystems; Btrfs, XFS, F2FS, exFAT, NTFS, HFS+, SquashFS and 9P stay.
      name = "laptop-trim-filesystems";
      patch = null;
      structuredExtraConfig = trim {
        off = [
          "OCFS2_FS" "GFS2_FS" "CEPH_FS" "AFS_FS" "CODA_FS" "ORANGEFS_FS"
          "NILFS2_FS" "JFS_FS" "ZONEFS_FS" "CRAMFS" "ROMFS_FS" "OMFS_FS"
          "AFFS_FS" "BEFS_FS" "BFS_FS" "EFS_FS" "MINIX_FS" "QNX4FS_FS"
          "QNX6FS_FS" "UFS_FS" "VXFS_FS" "HPFS_FS" "ADFS_FS"
        ];
        orphans = [ "CEPH_FSCACHE" "CEPH_FS_POSIX_ACL" "JFS_POSIX_ACL" "JFS_SECURITY" "OCFS2_DEBUG_MASKLOG" ];
      };
    }
    {
      name = "laptop-voluntary-preemption";
      patch = null;
      structuredExtraConfig = {
        PREEMPT_DYNAMIC = lib.mkForce lib.kernel.no;
        PREEMPT = lib.mkForce lib.kernel.no;
        PREEMPT_LAZY = lib.mkForce lib.kernel.no;
        PREEMPT_VOLUNTARY = lib.mkForce lib.kernel.yes;
      };
    }
    {
      # AMD platforms, hypervisor guests and Nouveau: an Intel laptop on NVIDIA's driver.
      name = "laptop-trim-amd-guests-nouveau";
      patch = null;
      structuredExtraConfig = trim {
        off = [
          "KVM_AMD" "X86_AMD_PLATFORM_DEVICE" "AMD_MEM_ENCRYPT" "AMD_PMC" "AMD_IOMMU"
          "XEN" "HYPERV" "KVM_GUEST" "DRM_NOUVEAU"
        ];
        orphans = [ "KVM_AMD_SEV" "SEV_GUEST" "DRM_HYPERV" "FB_HYPERV" "DRM_NOUVEAU_SVM" ];
      };
    }
    {
      # Otherwise the boot greeter power-cycles the eDP panel; see docs/hyprland.md.
      name = "drm-max-bpc-change-is-a-mode-change";
      patch = ../../patches/linux/drm-max-bpc-change-is-a-mode-change.patch;
    }
    {
      # Experiment against intermittent touchpad lag; see docs/nix.md.
      name = "i2c-force-100khz-elan-04f3-311c";
      patch = ../../patches/linux/i2c-force-100khz-elan-04f3-311c.patch;
    }
    {
      # Otherwise one failed monitor add makes every later one Busy; see docs/airpods.md.
      name = "bluetooth-mgmt-failed-monitor-add-leaves-no-pending";
      patch = ../../patches/linux/bluetooth-mgmt-failed-monitor-add-leaves-no-pending.patch;
    }
    {
      # Otherwise dell-wmi drops Fn+Esc and nothing can announce the mode; see docs/desktopctl.md.
      name = "dell-wmi-report-fn-lock-button";
      patch = ../../patches/linux/dell-wmi-report-fn-lock-button.patch;
    }
  ];

  # The i7-12700H's blob alone; the full bundle is 15 MiB of every boot's initrd.
  hardware.cpu.intel.microcodePackage = pkgs.microcode-intel.overrideAttrs {
    preInstall = "find intel-ucode -type f ! -name 06-9a-03 -delete";
  };

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
    # The module's own softdep must carry nvidia-uvm; see docs/nvidia.md.
    package = config.boot.kernelPackages.nvidiaPackages.stable.overrideAttrs (old: {
      passthru = old.passthru // {
        open = old.passthru.open.overrideAttrs (open: {
          patches = open.patches ++ [ ../../patches/nvidia/open-softdep-post-nvidia-uvm.patch ];
        });
      };
    });
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
  hardware.display.edid.packages = [ pkgs.laptop-panel-edid ];
  hardware.display.outputs.eDP-1.edid = "panel.bin";
  # Interim: drops nixpkgs' eager nvidia_uvm, which udev now loads; see docs/nvidia.md.
  environment.etc."modules-load.d/nixos.conf".source = lib.mkForce (
    config.boot.kernelModules
    |> lib.lists.remove "nvidia_uvm"
    |> lib.strings.concatLines
    |> pkgs.writeText "nixos.conf"
  );
  environment.sessionVariables.__EGL_VENDOR_LIBRARY_FILENAMES =
    "/run/opengl-driver/share/glvnd/egl_vendor.d/50_mesa.json";
  # GTK's Vulkan renderer wakes the dGPU on every launch; see docs/nvidia.md.
  environment.sessionVariables.GSK_RENDERER = "gl";
  # Restoring the keyboard backlight held sysinit.target for ~1.2s.
  systemd.units."systemd-backlight@leds:dell::kbd_backlight.service".enable = false;

  # Pinned: IP geolocation places Spectrum's IPv4 addresses in Colorado.
  time.timeZone = "America/New_York";

  services.openssh.enable = lib.mkForce false;

  powerManagement.powertop.enable = true;

  # Touchpad PM pin (docs/nix.md), colon-free GPU names (docs/nvidia.md), readable Fn-lock (docs/desktopctl.md).
  services.udev.extraRules = /* udev */ ''
    ACTION=="add|change", SUBSYSTEM=="pci", KERNEL=="0000:00:15.1", ATTR{power/control}="on"
    SUBSYSTEM=="drm", ENV{DEVTYPE}=="drm_minor", KERNEL=="card[0-9]*", SUBSYSTEMS=="pci", DRIVERS=="i915", SYMLINK+="dri/intel-gpu"
    SUBSYSTEM=="drm", ENV{DEVTYPE}=="drm_minor", KERNEL=="card[0-9]*", SUBSYSTEMS=="pci", DRIVERS=="nvidia", SYMLINK+="dri/nvidia-gpu"
    ACTION=="add", SUBSYSTEM=="firmware-attributes", KERNEL=="dell-wmi-sysman", TAG+="systemd", ENV{SYSTEMD_WANTS}+="fn-lock-readable.service"
  '';

  systemd.services.fn-lock-readable = {
    description = "Let desktopctl read the Fn-lock mode";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${lib.getExe' pkgs.coreutils "chmod"} 0444 /sys/devices/virtual/firmware-attributes/dell-wmi-sysman/attributes/FnLockMode/current_value";
      # The device appears before the driver adds its attributes under it.
      Restart = "on-failure";
      RestartSec = 1;
    };
  };

  # Must hang off powertop.service itself; see docs/nix.md.
  powerManagement.powertop.postStart = /* bash */ ''
    echo on > /sys/bus/pci/devices/0000:00:15.1/power/control
  '';

  # ── Power profiles ──────────────────────────────────────────
  # Everything here follows power-profiles-daemon; see docs/laptop-power.md.
  services.scx-loader = {
    enable = true;
    config = {
      default_sched = "scx_lavd";
      scheds.scx_lavd.auto_mode = [ "--autopower" ];
    };
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
        # 115 W is the firmware's PL1; the lower of MMIO and MSR applies, so MMIO alone caps.
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

  # ── Fingerprint auth ────────────────────────────────────────
  # Goodix 27c6:63ac is in upstream libfprint; no TOD.
  services.fprintd = {
    enable = true;
    tod.enable = false;
  };

  # ── Face auth ───────────────────────────────────────────────
  # IR stream of the Integrated_Webcam_HD; the bare /dev/videoN can renumber.
  services.howdy = {
    enable = true;
    control = "sufficient";
    settings.video.device_path = "/dev/v4l/by-path/pci-0000:00:14.0-usb-0:6:1.2-video-index0";
  };
  services.linux-enable-ir-emitter.enable = true;

  # Otherwise howdy lands in every PAM service, the greeter included.
  security.pam.howdy.enable = false;

  security.pam.services = lib.mkMerge [
    {
      # SDDM uses `login`; the greeter must always accept a password.
      login.fprintAuth = false;

      # hyprlock talks to fprintd natively, in parallel with this PAM stack.
      hyprlock = {
        fprintAuth = false;
        howdy.enable = true;
      };
    }
    (genAttrs [ "sudo" "polkit-1" ] (service: {
      fprintAuth = true;
      howdy.enable = true;
      # Face gives up in seconds; the reader waits 30.
      rules.auth.howdy.order = config.security.pam.services.${service}.rules.auth.fprintd.order - 1;
    }))
  ];

  # nixpkgs' polkit module opens its sandbox for fprintd and u2f, not howdy.
  systemd.services."polkit-agent-helper@".serviceConfig = {
    PrivateDevices = false;
    DeviceAllow = [ "char-video4linux rw" ];
  };

  # ── Polkit — local biometric management + Dell battery control ─
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

      // Same for howdy: -U would act on another user's face models.
      if (action.id === "org.freedesktop.policykit.exec" &&
          /\/howdy$/.test(action.lookup("program")) &&
          /^\S*\/howdy\s+(--plain\s+list|-y\s+--plain\s+(add|remove\s+[0-9]+))\s*$/.test(action.lookup("command_line")) &&
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
