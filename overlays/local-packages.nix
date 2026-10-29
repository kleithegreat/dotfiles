final: prev: {
  bend2-lsp = final.callPackage ../pkgs/bend2-lsp { };
  bambu-studio = final.callPackage ../pkgs/bambu-studio {
    upstreamBambuStudio = prev.bambu-studio;
  };
  # It only runs the host-arch qemu-system; full qemu is another ~1 GiB.
  claude-desktop = prev.claude-desktop.override { qemu = final.qemu_kvm; };
  comfyui = final.callPackage ../pkgs/comfyui { };
  # A field code cannot survive the dispatch string; see docs/hyprland.md.
  code-hypr = final.writeShellApplication {
    name = "code-hypr";
    text = /* bash */ ''
      cmd=code
      for arg in "$@"; do
        cmd="$cmd $(printf '%q' "$arg")"
      done
      hyprctl dispatch "hl.dsp.exec_cmd([==[$cmd]==])"
    '';
  };
  dd-cli = final.callPackage ../pkgs/dd-cli { };
  desktopctl = final.callPackage ../desktopctl { };
  helium = final.callPackage ../pkgs/helium { };
  kernel-oom-notifier = final.callPackage ../pkgs/kernel-oom-notifier { };
  linux-devmgmt = final.optimize.ccache (final.callPackage ../pkgs/linux-devmgmt { });
  lmstudio = final.callPackage ../pkgs/lmstudio {
    upstreamLmstudio = prev.lmstudio;
  };
  macos-vm = final.callPackage ../pkgs/macos-vm { };
  neuwaita = final.callPackage ../pkgs/neuwaita { };
  qemu-reims-vgpu = final.callPackage ../pkgs/qemu-reims-vgpu { };
  srbminer = final.callPackage ../pkgs/srbminer { };
  # kdePackages.sddm is this scope's wrapper. Without the patch, logind's
  # TerminateSession (Vicinae's Log Out) leaves no greeter; see docs/hyprland.md.
  qt6Packages = prev.qt6Packages.overrideScope (qfinal: qprev: {
    sddm-unwrapped = (final.optimize.ccache qprev.sddm-unwrapped).overrideAttrs (old: {
      patches = (old.patches or [ ]) ++ [ ../patches/sddm/sddm-helper-signal-is-not-auth-error.patch ];
    });
  });
  reims-vgpu = final.optimize.sccache (final.callPackage ../pkgs/reims-vgpu { });
  sddm-theme = final.callPackage ../pkgs/sddm-theme { };
  sf-pro = final.callPackage ../pkgs/sf-pro { };
  snappy-switcher = final.optimize.ccache (final.callPackage ../pkgs/snappy-switcher { });
  tree-sitter-bend2 = final.callPackage ../pkgs/tree-sitter-bend2 { };
  unearth = final.optimize.sccache (final.callPackage ../pkgs/unearth { });
  unearth-vicinae = final.callPackage ../pkgs/unearth/vicinae { };
  zsh-share-only = final.runCommand "zsh-share-only" { } /* bash */ ''
    mkdir --parents "$out/share"
    ln --symbolic ${final.zsh}/share/zsh "$out/share/zsh"
  '';
}
