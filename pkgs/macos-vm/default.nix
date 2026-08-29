{
  writeShellApplication,
  runCommand,
  fetchFromGitHub,
  reims-vgpu,
  dmg2img,
  python3,
}:

let
  osxKvm = fetchFromGitHub {
    owner = "kholia";
    repo = "OSX-KVM";
    rev = "4c378a4b5e0b219783683012bec680325eb40719";
    hash = "sha256-BmMWWGkNtZwEH9utoc3Mj5gGCjlgIicGsTEPxAxG7hw=";
  };

  # OpenCore's boot disk and the OVMF pair are prebuilt binaries: OSX-KVM is
  # where they come from, and only these four files are wanted out of it.
  bootFiles = runCommand "osx-kvm-boot-files" { } ''
    install -D --mode=444 --target-directory="$out" \
      ${osxKvm}/OVMF_CODE_4M.fd \
      ${osxKvm}/OVMF_VARS-1920x1080.fd \
      ${osxKvm}/OpenCore/OpenCore.qcow2
    install -D --mode=444 ${osxKvm}/fetch-macOS-v2.py "$out/fetch-macOS.py"
  '';
in
writeShellApplication {
  name = "macos-vm";

  runtimeInputs = [
    reims-vgpu
    dmg2img
    python3
  ];

  text = /* bash */ ''
    boot=${bootFiles}

    # The guest is not reproducible and none of it lives in the store: the
    # system disk, OpenCore's boot disk, the OVMF variable store the firmware
    # writes to, and the recovery image all live here.
    state="''${MACOS_VM_DIR:-$HOME/vm/macos}"
    ram="''${MACOS_VM_RAM:-8G}"
    cpus="''${MACOS_VM_CPUS:-8}"
    size="''${MACOS_VM_DISK:-128G}"
    port="''${MACOS_VM_SSH_PORT:-2222}"

    args=()

    usage() {
      cat <<'EOF'
    usage: macos-vm fetch [RELEASE] | install | run [--console]

      fetch    download Apple's recovery image (default RELEASE: ventura, what
               reims-vgpu is developed against) and unpack it for the installer
      install  create the system disk and boot the recovery installer
      run      boot the installed guest on the reims-vgpu device, which opens
               its own Vulkan window; --console boots it on vmware-svga in a
               QEMU window instead, which is what shows OpenCore and anything
               before AppleParavirtGPU loads

    MACOS_VM_DIR=~/vm/macos  MACOS_VM_RAM=8G  MACOS_VM_CPUS=8
    MACOS_VM_DISK=128G  MACOS_VM_SSH_PORT=2222
    EOF
    }

    seed() {
      mkdir --parents "$state"
      # Both are written by the guest, so each gets a writable copy on first
      # use. OVMF_CODE is read-only and stays in the store.
      [ -e "$state/OpenCore.qcow2" ] \
        || install --mode=644 "$boot/OpenCore.qcow2" "$state/OpenCore.qcow2"
      [ -e "$state/OVMF_VARS.fd" ] \
        || install --mode=644 "$boot/OVMF_VARS-1920x1080.fd" "$state/OVMF_VARS.fd"
    }

    base_args() {
      args=(
        -enable-kvm
        -m "$ram"
        # The device reaches guest pages through this backend, and `share=on`
        # is what lets the Vulkan side import them as a dma-buf instead of
        # copying every frame.
        -object "memory-backend-memfd,id=reims-ram,size=$ram,share=on"
        -machine "q35,memory-backend=reims-ram"
        -cpu "Skylake-Client,-hle,-rtm,kvm=on,vendor=GenuineIntel,+invtsc,vmware-cpuid-freq=on,+ssse3,+sse4.2,+popcnt,+avx,+avx2,+aes,+xsave,+xsaveopt,check"
        # 8 is a ceiling, not a preference: the x86 guest's kext wedges in
        # StorageNode::init above it.
        -smp "$cpus,cores=$cpus,sockets=1"
        -device "qemu-xhci,id=xhci"
        -device "usb-kbd,bus=xhci.0"
        -device "usb-tablet,bus=xhci.0"
        -device "usb-ehci,id=ehci"
        -device "isa-applesmc,osk=ourhardworkbythesewordsguardedpleasedontsteal(c)AppleComputerInc"
        -drive "if=pflash,format=raw,readonly=on,file=$boot/OVMF_CODE_4M.fd"
        -drive "if=pflash,format=raw,file=$state/OVMF_VARS.fd"
        -smbios type=2
        -audiodev "pipewire,id=audio0,out.buffer-length=46440"
        -device "usb-audio,bus=xhci.0,audiodev=audio0,buffer=65536"
        -device "ich9-ahci,id=sata"
        -drive "id=OpenCoreBoot,if=none,format=qcow2,file=$state/OpenCore.qcow2"
        -device "ide-hd,bus=sata.2,drive=OpenCoreBoot"
        -drive "id=MacHDD,if=none,format=qcow2,file=$state/macos.qcow2"
        -device "ide-hd,bus=sata.4,drive=MacHDD"
        # macOS keys its network profile off the MAC, so a fresh one arrives in
        # the guest as an unconfigured second interface.
        -netdev "user,id=net0,ipv6=off,hostfwd=tcp::$port-:22"
        -device "virtio-net-pci,netdev=net0,id=net0,mac=52:54:00:c9:18:27"
        -serial mon:stdio
      )
    }

    console_display() {
      args+=(
        -device vmware-svga
        -display gtk
      )
    }

    vgpu_display() {
      # The device carries the only display: its UEFI GOP lives on the same PCI
      # function, and a second VGA would give the guest a second screen.
      # REIMS_VGPU_WINDOW makes the staticlib open the Vulkan window itself, so
      # QEMU owns no UI.
      export REIMS_VGPU_WINDOW=1
      args+=(
        -vga none
        -device "pci-bridge,chassis_nr=5,id=pci.5,bus=pcie.0,addr=1e.0"
        -device "reims-vgpu-pci,id=reimsvgpu,bus=pci.5,addr=00.0"
        -display none
      )
    }

    cmd_fetch() {
      release="ventura"
      [ "$#" -gt 0 ] && release="$1"
      mkdir --parents "$state"
      # The script's own menu path ignores --outdir and writes to the working
      # directory, so the working directory is how the destination is chosen.
      cd "$state"
      python3 "$boot/fetch-macOS.py" --shortname "$release"
      dmg=$(find "$state" -maxdepth 1 -name '*.dmg' -printf '%T@ %p\n' \
        | sort --reverse --numeric-sort | head --lines=1 | cut --delimiter=' ' --fields=2-)
      if [ -z "$dmg" ]; then
        echo "macos-vm: no recovery image downloaded" >&2
        exit 1
      fi
      dmg2img "$dmg" "$state/BaseSystem.img"
      echo "macos-vm: installer media ready at $state/BaseSystem.img"
    }

    cmd_install() {
      if [ ! -e "$state/BaseSystem.img" ]; then
        echo "macos-vm: no installer media; run 'macos-vm fetch' first" >&2
        exit 1
      fi
      seed
      [ -e "$state/macos.qcow2" ] || qemu-img create -f qcow2 "$state/macos.qcow2" "$size"
      base_args
      # The installer runs before AppleParavirtGPU exists in the guest, so it
      # only ever gets the console device.
      console_display
      args+=(
        -drive "id=InstallMedia,if=none,format=raw,file=$state/BaseSystem.img"
        -device "ide-hd,bus=sata.3,drive=InstallMedia"
      )
      exec qemu-system-x86_64 "''${args[@]}"
    }

    cmd_run() {
      if [ ! -e "$state/macos.qcow2" ]; then
        echo "macos-vm: no guest disk; run 'macos-vm install' first" >&2
        exit 1
      fi
      seed
      base_args
      if [ "''${1:-}" = "--console" ]; then
        console_display
      else
        vgpu_display
      fi
      exec qemu-system-x86_64 "''${args[@]}"
    }

    command="''${1:-}"
    [ "$#" -gt 0 ] && shift
    case "$command" in
      fetch) cmd_fetch "$@" ;;
      install) cmd_install "$@" ;;
      run) cmd_run "$@" ;;
      *) usage; exit 1 ;;
    esac
  '';
}
