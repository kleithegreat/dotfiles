{ config, pkgs, lib, ... }:

let
  laptopPowerProfile = pkgs.writeShellApplication {
    name = "laptop-power-profile";
    runtimeInputs = with pkgs; [ coreutils gnugrep gnused config.services.power-profiles-daemon.package ];
    text = ''
      set -euo pipefail

      profile_root=/sys/devices/system/cpu

      cpu_numbers() {
        for cpu_dir in "$profile_root"/cpu[0-9]*; do
          cpu_name=''${cpu_dir##*/cpu}
          printf '%s\n' "$cpu_name"
        done | sort -n
      }

      thread_sibling_count() {
        tr ',' '\n' < "$1" | wc -l
      }

      p_core_cpus() {
        for cpu in $(cpu_numbers); do
          siblings="$profile_root/cpu$cpu/topology/thread_siblings_list"
          [ -f "$siblings" ] || continue
          if [ "$(thread_sibling_count "$siblings")" -gt 1 ]; then
            printf '%s\n' "$cpu"
          fi
        done
      }

      all_hotpluggable_cpus() {
        for cpu in $(cpu_numbers); do
          online_path="$profile_root/cpu$cpu/online"
          [ -f "$online_path" ] && printf '%s\n' "$cpu"
        done
      }

      is_efficiency_mode() {
        local cpu online_path
        local saw_hotpluggable_p_core=0

        for cpu in $(p_core_cpus); do
          online_path="$profile_root/cpu$cpu/online"
          if [ -f "$online_path" ]; then
            saw_hotpluggable_p_core=1
            if [ "$(cat "$online_path")" != "0" ]; then
              return 1
            fi
          fi
        done

        [ "$saw_hotpluggable_p_core" -eq 1 ]
      }

      set_cpu_online() {
        local cpu="$1"
        local value="$2"
        local online_path="$profile_root/cpu$cpu/online"

        [ -f "$online_path" ] || return 0
        printf '%s' "$value" > "$online_path"
      }

      enable_all_hotpluggable_cpus() {
        local cpu
        for cpu in $(all_hotpluggable_cpus); do
          set_cpu_online "$cpu" 1
        done
      }

      enable_standard_profile() {
        local profile="$1"

        enable_all_hotpluggable_cpus
        powerprofilesctl set "$profile"
      }

      enable_efficiency_profile() {
        local cpu

        enable_all_hotpluggable_cpus
        powerprofilesctl set power-saver

        for cpu in $(p_core_cpus); do
          set_cpu_online "$cpu" 0
        done
      }

      get_profile() {
        if is_efficiency_mode; then
          printf 'e-core-only\n'
        else
          powerprofilesctl get
        fi
      }

      usage() {
        printf 'usage: laptop-power-profile get | set <performance|balanced|power-saver|e-core-only>\n' >&2
        exit 2
      }

      case "''${1:-}" in
        get)
          [ "$#" -eq 1 ] || usage
          get_profile
          ;;
        set)
          [ "$#" -eq 2 ] || usage
          case "$2" in
            performance|balanced|power-saver)
              enable_standard_profile "$2"
              ;;
            e-core-only)
              enable_efficiency_profile
              ;;
            *)
              usage
              ;;
          esac
          ;;
        *)
          usage
          ;;
      esac
    '';
  };
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
        # Keep the laptop on voluntary preemption instead of the repo-wide
        # BORE + full-preempt desktop policy.
        PREEMPT_DYNAMIC = lib.mkForce lib.kernel.no;
        PREEMPT = lib.mkForce lib.kernel.no;
        PREEMPT_LAZY = lib.mkForce lib.kernel.no;
        PREEMPT_VOLUNTARY = lib.mkForce lib.kernel.yes;

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

        # The laptop uses the NVIDIA stack, so Nouveau is unused.
        DRM_NOUVEAU = lib.mkForce lib.kernel.no;
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

  # Laptop overrides — disable laptop-only remote login.
  services.openssh.enable = lib.mkForce false;

  services.power-profiles-daemon.enable = true;

  # Runs `powertop --auto-tune` at boot to enable runtime PM on devices that
  # don't default to it (NVMe, audio codec, sensor hub, etc.)
  powerManagement.powertop.enable = true;
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
  # power-profile popup doesn't trigger an auth dialog on every open. The
  # laptop-only power-profile helper also runs through pkexec so the shell can
  # switch the P-core mask without prompting.
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

      if (action.id === "org.freedesktop.policykit.exec" &&
          /\/laptop-power-profile$/.test(action.lookup("program")) &&
          subject.user === "kevin" && subject.local && subject.active) {
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
    laptopPowerProfile
  ];
}
