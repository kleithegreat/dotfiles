{ config, pkgs, lib, march, ... }:

let
  optimizedKernelPackages =
    if march == null then
      pkgs.linuxPackages
    else
      pkgs.linuxPackagesFor ((pkgs.linuxPackages.kernel.override {
        # Linux 6.18 on this pinned nixpkgs revision still ships a few stale
        # Kconfig symbols, so let Kconfig drop them while keeping our explicit
        # laptop-only overrides below.
        ignoreConfigErrors = true;
      }).overrideAttrs (old: {
        extraMakeFlags = (old.extraMakeFlags or [ ]) ++ [
          "KCFLAGS=-O3 -march=${march}"
          "KRUSTFLAGS=-Ctarget-cpu=${march}"
        ];
      }));
in
{
  imports = [
    ./fan-control.nix
  ];

  # Hardware — from nixos-generate-config
  boot.initrd.availableKernelModules = [ "xhci_pci" "thunderbolt" "vmd" "nvme" "rtsx_pci_sdmmc" ];
  # Keep the stock kernel version/package set, but compile it for the laptop CPU.
  boot.kernelPackages = optimizedKernelPackages;
  boot.kernelPatches = [
    {
      name = "laptop-intel-only-kernel-config";
      patch = null;
      structuredExtraConfig = {
        # Keep Intel KVM host support, but drop AMD-only host features.
        KVM_AMD = lib.mkForce lib.kernel.no;
        X86_AMD_PLATFORM_DEVICE = lib.mkForce lib.kernel.no;
        AMD_MEM_ENCRYPT = lib.mkForce lib.kernel.no;
        AMD_PMC = lib.mkForce lib.kernel.no;
        AMD_IOMMU = lib.mkForce lib.kernel.no;

        # This host only runs on bare metal, so guest-hypervisor support is dead
        # weight even though it still hosts local KVM guests.
        XEN = lib.mkForce lib.kernel.no;
        HYPERV = lib.mkForce lib.kernel.no;
        KVM_GUEST = lib.mkForce lib.kernel.no;

        # The laptop uses the proprietary NVIDIA stack, so Nouveau is unused.
        DRM_NOUVEAU = lib.mkForce lib.kernel.no;
      };
    }
  ];
  boot.kernelModules = [ "kvm-intel" ];

  fileSystems."/" = {
    device = "/dev/disk/by-uuid/b570af09-b288-4994-8373-f87cbe7ec964";
    fsType = "ext4";
  };

  fileSystems."/boot/efi" = {
    device = "/dev/disk/by-uuid/D85B-8832";
    fsType = "vfat";
    options = [ "fmask=0077" "dmask=0077" ];
  };

  zramSwap.enable = true;
  zramSwap.memoryPercent = 50;

  hardware.enableRedistributableFirmware = true;
  hardware.cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;

  # Boot — GRUB with EFI (for Windows dual-boot)
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

  # NVIDIA hybrid graphics (Intel Iris Xe + RTX 3050 Mobile)
  hardware.graphics.enable = true;
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

  # Laptop overrides — disable services enabled in shared configuration.nix
  hardware.bluetooth.powerOnBoot = lib.mkForce false;
  services.samba.enable = lib.mkForce false;
  services.openssh.enable = lib.mkForce false;

  # Large local builds already saturate this laptop internally, so serialize
  # derivations and let each one keep full core parallelism.
  nix.settings.max-jobs = 1;

  services.power-profiles-daemon.enable = true;

  # Runs `powertop --auto-tune` at boot to enable runtime PM on devices that
  # don't default to it (NVMe, audio codec, sensor hub, etc.)
  powerManagement.powertop.enable = true;
  networking.useDHCP = lib.mkDefault true;
  # Bound rare upstream tailscaled shutdown hangs so reboot does not wait for
  # the full systemd default stop timeout.
  systemd.services.tailscaled.serviceConfig.TimeoutStopSec = "15s";

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

  # ── Polkit — local fingerprint management + Dell battery reads ─
  # Allow the active local desktop user to enroll/delete their own fingerprints
  # without bouncing through the external auth agent on every action.
  # smbios-battery-ctl needs root to read SMBIOS tables (WMI/dcdbas), but
  # --get-charging-cfg is read-only.  Auto-approve it so the Quickshell
  # power-profile popup doesn't trigger an auth dialog on every open.
  # --set-* operations are unaffected and still require authentication.
  security.polkit.extraConfig = ''
    polkit.addRule(function(action, subject) {
      if (action.id === "net.reactivated.fprint.device.enroll" &&
          subject.user === "kevin" && subject.local && subject.active) {
        return polkit.Result.YES;
      }

      if (action.id === "org.freedesktop.policykit.exec" &&
          /\/smbios-battery-ctl$/.test(action.lookup("program")) &&
          /\bsmbios-battery-ctl\s+--get-charging-cfg\s*$/.test(action.lookup("command_line")) &&
          subject.isInGroup("users")) {
        return polkit.Result.YES;
      }
    });
  '';

  # ── Captive Portal Browser ──────────────────────────────────
  # Dedicated Chromium instance for logging into captive portals
  # (hotel/airport WiFi) without messing with your DNS settings.
  # Uses NetworkManager to auto-detect DNS — just run `captive-browser`.
  programs.captive-browser = {
    enable = true;
    interface = "wlp0s20f3";
  };

  environment.systemPackages = with pkgs; [
    libsmbios
  ];
}
