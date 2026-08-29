{ pkgs, lib, ... }:

let
  # `desktopctl` implements the profile switch (desktopctl/src/bin/
  # laptop-power-profile), but arrives through home-manager. Expose just that
  # one binary system-wide: the polkit rule below grants passwordless pkexec by
  # program path, so keeping the privileged entry point in its own binary is
  # what stops that grant reaching every other desktopctl subcommand.
  laptopPowerProfile = pkgs.runCommand "laptop-power-profile" { } ''
    mkdir -p "$out/bin"
    ln -s ${pkgs.optimized.desktopctl}/bin/laptop-power-profile "$out/bin/laptop-power-profile"
  '';
in {
  imports = [
    ./fan-control.nix
  ];

  # Hardware — from nixos-generate-config
  boot.initrd.availableKernelModules = [ "xhci_pci" "thunderbolt" "vmd" "nvme" "rtsx_pci_sdmmc" ];
  boot.kernelPatches = [
    {
      name = "laptop-intel-only-kernel-config";
      patch = null;
      structuredExtraConfig = {
        # Keep the laptop on voluntary preemption for its mobile hybrid-GPU path.
        PREEMPT_DYNAMIC = lib.mkForce lib.kernel.no;
        PREEMPT = lib.mkForce lib.kernel.no;
        PREEMPT_LAZY = lib.mkForce lib.kernel.no;
        PREEMPT_VOLUNTARY = lib.mkForce lib.kernel.yes;

        # Keep Intel KVM host support, but drop AMD-only host features.
        KVM_AMD = lib.mkForce lib.kernel.no;
        X86_AMD_PLATFORM_DEVICE = lib.mkForce lib.kernel.no;
        AMD_MEM_ENCRYPT = lib.mkForce lib.kernel.no;
        KVM_AMD_SEV = lib.mkForce lib.kernel.unset;
        SEV_GUEST = lib.mkForce lib.kernel.unset;
        AMD_PMC = lib.mkForce lib.kernel.no;
        AMD_IOMMU = lib.mkForce lib.kernel.no;

        # This host only runs on bare metal, so guest-hypervisor support is dead
        # weight even though it still hosts local KVM guests.
        XEN = lib.mkForce lib.kernel.no;
        HYPERV = lib.mkForce lib.kernel.no;
        DRM_HYPERV = lib.mkForce lib.kernel.unset;
        FB_HYPERV = lib.mkForce lib.kernel.unset;
        KVM_GUEST = lib.mkForce lib.kernel.no;

        # The laptop uses the NVIDIA stack, so Nouveau is unused.
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
    options = [ "fmask=0077" "dmask=0077" ];
  };

  # NVIDIA hybrid graphics (Intel Iris Xe + RTX 3050 Mobile)
  hardware.graphics = {
    enable = true;
    # Mesa does not ship iHD_drv_video.so; intel-media-driver backs the
    # LIBVA_DRIVER_NAME=iHD selection in hosts/laptop/env.lua.
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

  # Only this host travels, so only this host tracks the timezone by
  # location; the desktop pins `time.timeZone` instead.
  services.automatic-timezoned.enable = true;

  # Laptop overrides — disable laptop-only remote login.
  services.openssh.enable = lib.mkForce false;

  services.power-profiles-daemon.enable = true;

  # Runs `powertop --auto-tune` at boot to enable runtime PM on devices that
  # don't default to it (NVMe, audio codec, sensor hub, etc.)
  powerManagement.powertop.enable = true;

  # ── Touchpad responsiveness ─────────────────────────────────
  # `powertop --auto-tune` sets power/control=auto on *every* PCI device, 00:15.1
  # included — the Alder Lake LPSS I2C controller the ELAN touchpad hangs off
  # (.../0000:00:15.1/i2c_designware.1/i2c-2/i2c-VEN_04F3:00). The designware
  # adapter is slow to leave runtime suspend, so the first reports after an idle
  # stretch arrive late and the cursor stutters before catching up. Upstream hit
  # the same wall and removed runtime PM from i2c-hid outright, measuring "little
  # to none" energy saved, so pin this one controller to `on` and let powertop
  # tune everything else.
  #
  # Two mechanisms because neither covers the other's case: the udev rule catches
  # probe and re-probe, and the ExecStartPost re-asserts the value at boot, where
  # powertop runs long after udev has settled.
  services.udev.extraRules = ''
    ACTION=="add|change", SUBSYSTEM=="pci", KERNEL=="0000:00:15.1", ATTR{power/control}="on"
  '';

  # Hang the re-assert off powertop.service itself rather than racing it from a
  # separate unit. A separate unit cannot win here: powertop.service is both
  # WantedBy= and After= multi-user.target, so anything WantedBy that target must
  # start before it, and ordering After=powertop.service closes a cycle that
  # systemd breaks by silently deleting the job -- which is exactly what happened
  # (`Found ordering cycle ... deleted to break ordering cycle`), leaving the pin
  # dead at every boot while looking fine after a `switch`. ExecStartPost runs
  # inside powertop's own transaction, so the ordering is guaranteed by
  # construction instead of negotiated.
  systemd.services.powertop.serviceConfig.ExecStartPost =
    pkgs.writeShellScript "touchpad-i2c-pin-runtime-pm" ''
      echo on > /sys/bus/pci/devices/0000:00:15.1/power/control
    '';

  # Kept for the BIOS/EC regions and the Goodix fingerprint sensor, all of which
  # it does enumerate as updatable.
  #
  # It will NOT show the ELAN touchpad, and that is not a misconfiguration: the
  # elantp plugin is Ready and i2c_dev is loaded, but fwupd 2.1.6's quirk DB
  # carries 30 ELAN entries and 04F3:311C is not one of them, so nothing claims
  # the device. That matters because 311C is the part with the documented
  # firmware bug -- 0x000b stalls into an "inertia" lag every few minutes, which
  # libinput reports as rate-limited "Touch jump detected and discarded". There
  # is no LVFS path to 0x000c for it. Reaching it would mean hand-writing a quirk
  # and flashing an unofficial blob meant for the 9510/5560, which is precisely
  # what bricked this same part into bootloader mode (04F3:0400) in fwupd#5281.
  # Don't. The runtime-PM pin above is the supported lever.
  services.fwupd.enable = true;

  # ── Fingerprint auth ────────────────────────────────────────
  # Goodix 27c6:63ac is supported by upstream libfprint, so keep TOD disabled.
  services.fprintd = {
    enable = true;
    tod.enable = false;
  };

  security.pam.services = {
    # SDDM authenticates through the `login` PAM stack. Keep fingerprint auth
    # off there so the greeter always preserves password login.
    login.fprintAuth = false;

    sudo.fprintAuth = true;
    polkit-1.fprintAuth = true;

    # Hyprlock uses its native fprintd integration for parallel fingerprint
    # unlock, while PAM remains password-only as a fallback path.
    hyprlock.fprintAuth = false;
  };

  # ── Polkit — local fingerprint management + Dell battery control ─
  # Allow the active local desktop user to enroll/delete their own fingerprints
  # without bouncing through the external auth agent on every action.
  # smbios-battery-ctl needs root for the SMBIOS tables (WMI/dcdbas), so the
  # Quickshell charge-limit toggle would raise a dialog on every flip. The
  # grant enumerates whole argument forms rather than a program path:
  # smbios-battery-ctl also takes --password/--security-key, and a
  # program-wide grant would hand those to any caller. The
  # laptop-only power-profile helper also runs through pkexec so the shell can
  # switch the P-core mask without prompting.
  #
  # nixpkgs stopped installing the setuid pkexec wrapper by default; without it
  # every pkexec call above fails with "pkexec must be setuid root".
  security.polkit.enablePkexecWrapper = true;

  security.polkit.extraConfig = /* javascript */ ''
    polkit.addRule(function(action, subject) {
      if (action.id === "net.reactivated.fprint.device.enroll" &&
          subject.user === "kevin" && subject.local && subject.active) {
        return polkit.Result.YES;
      }

      if (action.id === "org.freedesktop.policykit.exec" &&
          /\/smbios-battery-ctl$/.test(action.lookup("program")) &&
          /^\S*\/smbios-battery-ctl\s+(--get-charging-cfg|--set-charging-mode=(primarily_ac|adaptive|custom|standard|express)(\s+--set-custom-charge-interval\s+[0-9]+\s+[0-9]+)?)\s*$/.test(action.lookup("command_line")) &&
          subject.user === "kevin" && subject.local && subject.active) {
        return polkit.Result.YES;
      }

      if (action.id === "org.freedesktop.policykit.exec" &&
          /\/laptop-power-profile$/.test(action.lookup("program")) &&
          subject.user === "kevin" && subject.local && subject.active) {
        return polkit.Result.YES;
      }
    });
  '';

  # ── Cornell eduroam ─────────────────────────────────────────
  # `domain-suffix-match` is the load-bearing line. Cornell's RADIUS server
  # presents a publicly-trusted InCommon/Sectigo chain, so `system-ca-certs`
  # on its own would accept any valid web certificate a rogue `eduroam` could
  # buy; pinning the server name is what stops one harvesting the MSCHAPv2
  # exchange and cracking the NetID password offline.
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
      # The outer identity stays anonymous so the NetID is never broadcast in
      # the clear; the realm is all Cornell's RADIUS needs to route on.
      "802-1x" = {
        eap = "peap";
        phase2-auth = "mschapv2";
        anonymous-identity = "anonymous@cornell.edu";
        identity = "kl2344@cornell.edu";
        password = "$CORNELL_NETID_PASSWORD";
        password-flags = 0;
        system-ca-certs = true;
        domain-suffix-match = "network-access.it.cornell.edu";
      };
      ipv4.method = "auto";
      ipv6.method = "auto";
    };
  };

  systemd.tmpfiles.rules = [ "d /etc/nm-secrets 0700 root root -" ];

  # ── Captive Portal Browser ──────────────────────────────────
  # Dedicated Chromium instance for logging into captive portals
  # (hotel/airport WiFi) without messing with your DNS settings.
  # Uses NetworkManager to auto-detect DNS — just run `captive-browser`.
  programs.captive-browser = {
    enable = true;
    interface = "wlp0s20f3";
  };

  # ── Steam ─────────────────────────────────────────────────────
  programs.steam = {
    enable = true;
    remotePlay.openFirewall = true;
    localNetworkGameTransfers.openFirewall = true;
    extest.enable = true;  # X11→uinput translation for controllers on Wayland
  };

  environment.systemPackages = with pkgs; [
    libsmbios
    laptopPowerProfile
  ];
}
