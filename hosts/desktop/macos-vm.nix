{ config, lib, pkgs, ... }:

let
  cfg = config.virtualisation.macosVm;

  diskPath = "${cfg.stateDir}/mac_hdd_ng.img";
  baseSystemDmg = "${cfg.stateDir}/BaseSystem.dmg";
  baseSystemImg = "${cfg.stateDir}/BaseSystem.img";
  osxKvmDir = "${cfg.stateDir}/OSX-KVM";
  openCoreImage = "${osxKvmDir}/OpenCore/OpenCore.qcow2";
  ovmfCode = "${osxKvmDir}/OVMF_CODE_4M.fd";
  ovmfVars = "${osxKvmDir}/OVMF_VARS-1920x1080.fd";

  prepareScript = pkgs.writeShellApplication {
    name = "macos-vm-prepare";
    runtimeInputs = with pkgs; [ coreutils dmg2img git qemu_kvm ];
    text = ''
      set -euo pipefail

      state_dir=${lib.escapeShellArg cfg.stateDir}
      osx_kvm_dir=${lib.escapeShellArg osxKvmDir}
      base_system_dmg=${lib.escapeShellArg baseSystemDmg}
      base_system_img=${lib.escapeShellArg baseSystemImg}
      disk_path=${lib.escapeShellArg diskPath}

      install -d -m 0750 "$state_dir"

      if [[ ! -d "$osx_kvm_dir/.git" ]]; then
        if [[ -e "$osx_kvm_dir" ]]; then
          echo "macos-vm-prepare: $osx_kvm_dir exists but is not a git checkout" >&2
          exit 1
        fi

        git clone --depth 1 --recursive ${lib.escapeShellArg cfg.osxKvmRepoUrl} "$osx_kvm_dir"
      fi

      if [[ ! -f "$base_system_img" ]]; then
        if [[ ! -f "$base_system_dmg" ]]; then
          (cd "$state_dir" && "$osx_kvm_dir/fetch-macOS-v2.py" --shortname ${lib.escapeShellArg cfg.shortName})
        fi

        dmg2img -i "$base_system_dmg" "$base_system_img"
      fi

      if [[ ! -f "$disk_path" ]]; then
        qemu-img create -f qcow2 "$disk_path" ${toString cfg.diskSizeGiB}G >/dev/null
      fi

      echo "macos-vm-prepare: ready"
      echo "  state: $state_dir"
      echo "  launch: macos-vm"
    '';
  };

  launcher = pkgs.writeShellApplication {
    name = "macos-vm";
    runtimeInputs = with pkgs; [ coreutils qemu_kvm ];
    text = ''
      set -euo pipefail

      disk_path=${lib.escapeShellArg diskPath}
      base_system_img=${lib.escapeShellArg baseSystemImg}
      open_core_image=${lib.escapeShellArg openCoreImage}
      ovmf_code=${lib.escapeShellArg ovmfCode}
      ovmf_vars=${lib.escapeShellArg ovmfVars}

      for required_file in "$disk_path" "$base_system_img" "$open_core_image" "$ovmf_code" "$ovmf_vars"; do
        if [[ ! -f "$required_file" ]]; then
          echo "macos-vm: missing $required_file" >&2
          echo "Run macos-vm-prepare first." >&2
          exit 1
        fi
      done

      qemu-system-x86_64 \
        -enable-kvm \
        -m ${toString cfg.memoryMiB} \
        -cpu Skylake-Client,-hle,-rtm,kvm=on,vendor=GenuineIntel,+invtsc,vmware-cpuid-freq=on,+ssse3,+sse4.2,+popcnt,+avx,+aes,+xsave,+xsaveopt,check \
        -machine q35 \
        -smp ${toString cfg.vcpus},cores=${toString cfg.vcpus},sockets=1 \
        -device qemu-xhci,id=xhci \
        -device usb-kbd,bus=xhci.0 \
        -device usb-tablet,bus=xhci.0 \
        -device usb-ehci,id=ehci \
        -device isa-applesmc,osk="ourhardworkbythesewordsguardedpleasedontsteal(c)AppleComputerInc" \
        -drive if=pflash,format=raw,readonly=on,file="$ovmf_code" \
        -drive if=pflash,format=raw,file="$ovmf_vars" \
        -smbios type=2 \
        -device ich9-intel-hda \
        -device hda-duplex \
        -device ich9-ahci,id=sata \
        -drive id=OpenCoreBoot,if=none,snapshot=on,format=qcow2,file="$open_core_image" \
        -device ide-hd,bus=sata.2,drive=OpenCoreBoot \
        -drive id=InstallMedia,if=none,file="$base_system_img",format=raw \
        -device ide-hd,bus=sata.3,drive=InstallMedia \
        -drive id=MacHDD,if=none,file="$disk_path",format=qcow2 \
        -device ide-hd,bus=sata.4,drive=MacHDD \
        -netdev user,id=net0,hostfwd=tcp::2222-:22 \
        -device virtio-net-pci,netdev=net0,id=net0,mac=${cfg.macAddress} \
        -device vmware-svga \
        -display gtk,show-tabs=off \
        -monitor stdio \
        "$@"
    '';
  };
in
{
  options.virtualisation.macosVm = {
    enable = lib.mkEnableOption "a desktop-local OSX-KVM macOS VM";

    user = lib.mkOption {
      type = lib.types.str;
      default = "kevin";
      description = "Normal user that owns the macOS VM state and launches QEMU.";
    };

    stateGroup = lib.mkOption {
      type = lib.types.str;
      default = "users";
      description = "Group owner for the macOS VM state directory.";
    };

    stateDir = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/macos-vm/sequoia";
      description = "Writable host-side state directory for OSX-KVM, installer media, and the guest disk.";
    };

    shortName = lib.mkOption {
      type = lib.types.str;
      default = "sequoia";
      description = "OSX-KVM fetch-macOS-v2.py shortname to download.";
    };

    osxKvmRepoUrl = lib.mkOption {
      type = lib.types.str;
      default = "https://github.com/kholia/OSX-KVM.git";
      description = "Upstream OSX-KVM repository cloned by macos-vm-prepare.";
    };

    diskSizeGiB = lib.mkOption {
      type = lib.types.ints.positive;
      default = 64;
      description = "Virtual size for the qcow2 macOS system disk.";
    };

    memoryMiB = lib.mkOption {
      type = lib.types.ints.positive;
      default = 12288;
      description = "Guest memory allocation in MiB.";
    };

    vcpus = lib.mkOption {
      type = lib.types.ints.positive;
      default = 4;
      description = "Number of virtual CPU threads and cores passed to QEMU.";
    };

    macAddress = lib.mkOption {
      type = lib.types.str;
      default = "52:54:00:c9:18:27";
      description = "Static guest NIC MAC address used by QEMU user networking.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = lib.attrByPath [ "users" "users" cfg.user "isNormalUser" ] false config;
        message = "virtualisation.macosVm.user must point at an existing normal user.";
      }
    ];

    users.users.${cfg.user}.extraGroups = lib.mkAfter [ "kvm" ];

    boot.extraModprobeConfig = ''
      options kvm ignore_msrs=1
    '';

    systemd.tmpfiles.rules = [
      "d ${cfg.stateDir} 0750 ${cfg.user} ${cfg.stateGroup} -"
    ];

    system.activationScripts.macosVm = lib.stringAfter [ "users" ] ''
      install -d -m 0750 -o ${lib.escapeShellArg cfg.user} -g ${lib.escapeShellArg cfg.stateGroup} ${lib.escapeShellArg cfg.stateDir}

      if [ ! -e ${lib.escapeShellArg diskPath} ]; then
        ${pkgs.qemu_kvm}/bin/qemu-img create -f qcow2 ${lib.escapeShellArg diskPath} ${toString cfg.diskSizeGiB}G >/dev/null
        chown ${lib.escapeShellArg cfg.user}:${lib.escapeShellArg cfg.stateGroup} ${lib.escapeShellArg diskPath}
        chmod 0640 ${lib.escapeShellArg diskPath}
      fi
    '';

    environment.systemPackages = [ prepareScript launcher ];
  };
}
