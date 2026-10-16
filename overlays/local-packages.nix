final: prev: {
  cantarell-fonts = prev.cantarell-fonts.overrideAttrs (old: {
    # The variable OTF fails in otfautohint on this pin; drop once a default build works.
    mesonFlags = (old.mesonFlags or []) ++ [
      "-Dbuildvf=false"
      "-Dbuildstatics=true"
    ];
  });

  bambu-studio = final.callPackage ../pkgs/bambu-studio {
    upstreamBambuStudio = prev.bambu-studio;
  };
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
  # Shares comfyui's CUDA set rather than pulling the default one in beside it.
  gpu-burn = prev.gpu-burn.override {
    config = prev.config // { cudaSupport = true; };
    cudaPackages = final.cudaPackages_13_3;
  };
  helium = final.callPackage ../pkgs/helium { };
  kernel-oom-notifier = final.callPackage ../pkgs/kernel-oom-notifier { };
  linux-devmgmt = final.callPackage ../pkgs/linux-devmgmt { };
  lmstudio = final.callPackage ../pkgs/lmstudio {
    upstreamLmstudio = prev.lmstudio;
  };
  macos-vm = final.callPackage ../pkgs/macos-vm { };
  neuwaita = final.callPackage ../pkgs/neuwaita { };
  qemu-reims-vgpu = final.callPackage ../pkgs/qemu-reims-vgpu { };
  # kdePackages.sddm is this scope's wrapper. Without the patch, logind's
  # TerminateSession (Vicinae's Log Out) leaves no greeter; see docs/hyprland.md.
  qt6Packages = prev.qt6Packages.overrideScope (qfinal: qprev: {
    sddm-unwrapped = qprev.sddm-unwrapped.overrideAttrs (old: {
      patches = (old.patches or [ ]) ++ [ ../patches/sddm/sddm-helper-signal-is-not-auth-error.patch ];
    });
  });
  reims-vgpu = final.callPackage ../pkgs/reims-vgpu { };
  sddm-theme = final.callPackage ../pkgs/sddm-theme { };
  sf-pro = final.callPackage ../pkgs/sf-pro { };
  snappy-switcher = final.callPackage ../pkgs/snappy-switcher { };
  zsh-share-only = final.runCommand "zsh-share-only" { } /* bash */ ''
    mkdir --parents "$out/share"
    ln --symbolic ${final.zsh}/share/zsh "$out/share/zsh"
  '';
}
