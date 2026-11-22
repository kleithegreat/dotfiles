{
  writeShellApplication,
  runCommand,
  fetchFromGitHub,
  qemu-reims-vgpu,
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

  # OVMF and OpenCore's boot disk are prebuilt; only these files are wanted from OSX-KVM.
  bootFiles = runCommand "osx-kvm-boot-files" { } /* bash */ ''
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
    qemu-reims-vgpu
    dmg2img
    python3
  ];

  text = /* bash */ ''
    boot=${bootFiles}

    # Guest state, never in the store (docs/macos-vm.md).
    state="''${MACOS_VM_DIR:-$HOME/vm/macos}"
    ram="''${MACOS_VM_RAM:-8G}"
    cpus="''${MACOS_VM_CPUS:-8}"
    size="''${MACOS_VM_DISK:-128G}"
    port="''${MACOS_VM_SSH_PORT:-2222}"

    args=()

    usage() {
      cat <<'EOF'
    usage: macos-vm fetch [RELEASE] | install | run [--console]

      fetch    download Apple's recovery image (default RELEASE: ventura) and unpack
               it for the installer
      install  create the system disk and boot the recovery installer
      run      boot the installed guest on the reims-vgpu device, which opens
               its own Vulkan window; --console boots it on vmware-svga in a
               QEMU window instead

    MACOS_VM_DIR=~/vm/macos  MACOS_VM_RAM=8G  MACOS_VM_CPUS=8
    MACOS_VM_DISK=128G  MACOS_VM_SSH_PORT=2222
    EOF
    }

    seed() {
      mkdir --parents "$state"
      # The guest writes both; OVMF_CODE is read-only and stays in the store.
      [ -e "$state/OpenCore.qcow2" ] \
        || install --mode=644 "$boot/OpenCore.qcow2" "$state/OpenCore.qcow2"
      [ -e "$state/OVMF_VARS.fd" ] \
        || install --mode=644 "$boot/OVMF_VARS-1920x1080.fd" "$state/OVMF_VARS.fd"
    }

    base_args() {
      args=(
        -enable-kvm
        -m "$ram"
        # `share=on` lets the Vulkan side import guest pages as a dma-buf instead of copying frames.
        -object "memory-backend-memfd,id=reims-ram,size=$ram,share=on"
        -machine "q35,memory-backend=reims-ram"
        -cpu "Skylake-Client,-hle,-rtm,kvm=on,vendor=GenuineIntel,+invtsc,vmware-cpuid-freq=on,+ssse3,+sse4.2,+popcnt,+avx,+avx2,+aes,+xsave,+xsaveopt,check"
        # A ceiling: more wedges the guest (docs/macos-vm.md).
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
        # Fixed: macOS keys its network profile off the MAC.
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
      # The only display (docs/macos-vm.md); under `-display none` the library opens its own windows.
      args+=(
        -vga none
        -device "apple-gfx-pci,id=gfx"
        # A guest woken from S3 never gets the device's display back.
        -global ICH9-LPC.disable_s3=1
        -display none
      )
    }

    cmd_fetch() {
      release="ventura"
      [ "$#" -gt 0 ] && release="$1"
      mkdir --parents "$state"
      # The script's menu path ignores --outdir (docs/macos-vm.md).
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
      # qemu-img accepts only -f, not --format.
      [ -e "$state/macos.qcow2" ] || qemu-img create -f qcow2 "$state/macos.qcow2" "$size"
      base_args
      # The installer runs before AppleParavirtGPU exists in the guest.
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
