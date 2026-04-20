{ config, lib, pkgs, ... }:

let
  cfg = config.virtualisation.windowsVm;
  firmwarePackage = pkgs.OVMFFull.fd;
  firmwareCode = "${firmwarePackage}/FV/OVMF_CODE.ms.fd";
  firmwareVarsTemplate = "${firmwarePackage}/FV/OVMF_VARS.ms.fd";

  diskPath = "${cfg.stateDir}/system.qcow2";
  isoDir = "${cfg.stateDir}/isos";
  unattendIsoPath = "${isoDir}/unattend.iso";
  tpmStateDir = "${cfg.stateDir}/tpm";
  ovmfVarsPath = "${cfg.stateDir}/OVMF_VARS.ms.fd";

  windowsVmLauncher = pkgs.writeShellApplication {
    name = "windows-vm";
    runtimeInputs = [ cfg.package pkgs.coreutils pkgs.swtpm ];
    text = ''
      set -euo pipefail

      disk_path=${lib.escapeShellArg diskPath}
      windows_iso=${lib.escapeShellArg cfg.windowsIsoPath}
      unattend_iso=${lib.escapeShellArg unattendIsoPath}
      iso_dir=${lib.escapeShellArg isoDir}
      tpm_dir=${lib.escapeShellArg tpmStateDir}
      ovmf_vars=${lib.escapeShellArg ovmfVarsPath}
      firmware_code=${lib.escapeShellArg firmwareCode}
      vm_name=${lib.escapeShellArg cfg.name}
      tpm_socket="$tpm_dir/swtpm.sock"

      if [[ ! -f "$disk_path" ]]; then
        echo "windows-vm: missing disk image at $disk_path" >&2
        echo "Run nixos-rebuild first so activation can create it." >&2
        exit 1
      fi

      if [[ ! -f "$ovmf_vars" ]]; then
        echo "windows-vm: missing OVMF vars at $ovmf_vars" >&2
        echo "Run nixos-rebuild first so activation can seed it." >&2
        exit 1
      fi

      install -d -m 0750 "$tpm_dir"
      rm -f "$tpm_socket"

      cleanup() {
        if [[ -n "''${swtpm_pid:-}" ]] && kill -0 "$swtpm_pid" 2>/dev/null; then
          kill "$swtpm_pid"
          wait "$swtpm_pid" || true
        fi
        rm -f "$tpm_socket"
      }

      trap cleanup EXIT INT TERM

      swtpm socket \
        --tpm2 \
        --tpmstate dir="$tpm_dir" \
        --ctrl type=unixio,path="$tpm_socket" \
        --log level=20 \
        &
      swtpm_pid=$!

      for _ in $(seq 1 50); do
        if [[ -S "$tpm_socket" ]]; then
          break
        fi
        sleep 0.1
      done

      if [[ ! -S "$tpm_socket" ]]; then
        echo "windows-vm: swtpm did not create $tpm_socket" >&2
        exit 1
      fi

      qemu_args=(
        -enable-kvm
        -name "$vm_name"
        -machine "type=q35,accel=kvm,smm=on"
        -cpu "host,hv_relaxed,hv_vapic,hv_spinlocks=0x1fff,hv_time"
        -smp ${toString cfg.vcpus}
        -m ${toString cfg.memoryMiB}
        -rtc "clock=host,base=localtime"
        -boot "menu=on"
        -drive "if=pflash,format=raw,readonly=on,file=$firmware_code"
        -drive "if=pflash,format=raw,file=$ovmf_vars"
        -chardev "socket,id=chrtpm,path=$tpm_socket"
        -tpmdev "emulator,id=tpm0,chardev=chrtpm"
        -device "tpm-tis,tpmdev=tpm0"
        -device "qemu-xhci,id=usb"
        -device usb-tablet
        -device "ich9-ahci,id=sata"
        -device ich9-intel-hda
        -device hda-duplex
        -netdev "user,id=net0,hostname=$vm_name"
        -device "e1000e,netdev=net0"
        -device virtio-rng-pci
        -drive "if=none,id=system,file=$disk_path,format=qcow2,discard=unmap,detect-zeroes=unmap"
        -device "nvme,drive=system,serial=${cfg.name}-system"
        -vga std
        -display "gtk,show-tabs=off"
      )

      if [[ -f "$windows_iso" ]]; then
        qemu_args+=(
          -drive "if=none,id=installer,file=$windows_iso,media=cdrom,format=raw,readonly=on"
          -device "ide-cd,bus=sata.0,drive=installer,bootindex=1"
        )
      else
        shopt -s nullglob
        fallback_isos=( "$iso_dir"/*.iso "$iso_dir"/*.ISO )
        shopt -u nullglob

        if (( ''${#fallback_isos[@]} == 1 )); then
          echo "windows-vm: configured ISO not found at $windows_iso; using ''${fallback_isos[0]} instead." >&2
          qemu_args+=(
            -drive "if=none,id=installer,file=''${fallback_isos[0]},media=cdrom,format=raw,readonly=on"
            -device "ide-cd,bus=sata.0,drive=installer,bootindex=1"
          )
        elif (( ''${#fallback_isos[@]} > 1 )); then
          echo "windows-vm: configured ISO not found at $windows_iso and multiple ISOs exist in $iso_dir; set virtualisation.windowsVm.windowsIsoPath explicitly. Booting disk only." >&2
        else
          echo "windows-vm: installer ISO not found at $windows_iso; booting disk only." >&2
        fi
      fi

      if [[ -f "$unattend_iso" ]]; then
        qemu_args+=( -drive "file=$unattend_iso,media=cdrom,readonly=on" )
      fi

${lib.concatMapStringsSep "\n" (arg: "      qemu_args+=( ${lib.escapeShellArg arg} )") cfg.extraArgs}

      qemu-system-x86_64 "''${qemu_args[@]}" "$@"
    '';
  };
in
{
  options.virtualisation.windowsVm = {
    enable = lib.mkEnableOption "a declarative local Windows QEMU VM";

    user = lib.mkOption {
      type = lib.types.str;
      default = "kevin";
      description = "Normal user that owns the VM state directory and launches QEMU.";
    };

    stateGroup = lib.mkOption {
      type = lib.types.str;
      default = "users";
      description = "Group owner for the VM state directory.";
    };

    name = lib.mkOption {
      type = lib.types.str;
      default = "windows11";
      description = "Guest name used in the QEMU window title and state directory.";
    };

    stateDir = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/windows-vm/${cfg.name}";
      description = "Writable host-side state directory for the guest disk, ISO staging, TPM state, and OVMF vars.";
    };

    windowsIsoPath = lib.mkOption {
      type = lib.types.str;
      default = "${isoDir}/windows11.iso";
      description = "Path to the Windows installer ISO that QEMU should attach when present.";
    };

    diskSizeGiB = lib.mkOption {
      type = lib.types.ints.positive;
      default = 50;
      description = "Virtual size for the qcow2 system disk that activation creates on first switch.";
    };

    memoryMiB = lib.mkOption {
      type = lib.types.ints.positive;
      default = 8192;
      description = "Guest memory allocation in MiB.";
    };

    vcpus = lib.mkOption {
      type = lib.types.ints.positive;
      default = 2;
      description = "Number of virtual CPUs passed to QEMU.";
    };

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.qemu_kvm;
      description = "QEMU package used for both qemu-img at activation time and qemu-system-x86_64 at runtime.";
    };

    extraArgs = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Extra arguments appended to the generated QEMU invocation.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = lib.attrByPath [ "users" "users" cfg.user "isNormalUser" ] false config;
        message = "virtualisation.windowsVm.user must point at an existing normal user.";
      }
    ];

    users.users.${cfg.user}.extraGroups = lib.mkAfter [ "kvm" ];

    systemd.tmpfiles.rules = [
      "d ${cfg.stateDir} 0750 ${cfg.user} ${cfg.stateGroup} -"
      "d ${isoDir} 0750 ${cfg.user} ${cfg.stateGroup} -"
      "d ${tpmStateDir} 0750 ${cfg.user} ${cfg.stateGroup} -"
    ];

    system.activationScripts.windowsVm = lib.stringAfter [ "users" ] ''
      install -d -m 0750 -o ${lib.escapeShellArg cfg.user} -g ${lib.escapeShellArg cfg.stateGroup} ${lib.escapeShellArg cfg.stateDir}
      install -d -m 0750 -o ${lib.escapeShellArg cfg.user} -g ${lib.escapeShellArg cfg.stateGroup} ${lib.escapeShellArg isoDir}
      install -d -m 0750 -o ${lib.escapeShellArg cfg.user} -g ${lib.escapeShellArg cfg.stateGroup} ${lib.escapeShellArg tpmStateDir}

      if [ ! -e ${lib.escapeShellArg ovmfVarsPath} ]; then
        install -m 0640 -o ${lib.escapeShellArg cfg.user} -g ${lib.escapeShellArg cfg.stateGroup} ${lib.escapeShellArg firmwareVarsTemplate} ${lib.escapeShellArg ovmfVarsPath}
      fi

      if [ ! -e ${lib.escapeShellArg diskPath} ]; then
        ${cfg.package}/bin/qemu-img create -f qcow2 ${lib.escapeShellArg diskPath} ${toString cfg.diskSizeGiB}G >/dev/null
        chown ${lib.escapeShellArg cfg.user}:${lib.escapeShellArg cfg.stateGroup} ${lib.escapeShellArg diskPath}
        chmod 0640 ${lib.escapeShellArg diskPath}
      fi
    '';

    environment.systemPackages = [ windowsVmLauncher ];
  };
}
