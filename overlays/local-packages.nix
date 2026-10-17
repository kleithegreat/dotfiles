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
  linux-devmgmt = final.optimize.ccache (final.callPackage ../pkgs/linux-devmgmt { });
  lmstudio = final.callPackage ../pkgs/lmstudio {
    upstreamLmstudio = prev.lmstudio;
  };
  macos-vm = final.callPackage ../pkgs/macos-vm { };
  neuwaita = final.callPackage ../pkgs/neuwaita { };
  qemu-reims-vgpu = final.callPackage ../pkgs/qemu-reims-vgpu { };
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
  unearth = final.optimize.sccache (final.callPackage ../pkgs/unearth {
    # EmbeddingGemma 2 needs v0.7.0; drop once nixpkgs has it.
    llama-cpp = (final.optimize.ccache prev.llama-cpp).overrideAttrs (old: {
      version = "0.7.0";
      src = final.fetchFromGitHub {
        owner = "ggml-org";
        repo = "llama.cpp";
        tag = "v0.7.0";
        hash = "sha256-pEDYgI3AMTU+cekvRX7NNt5wddznydQSNuerswvEpsA=";
      };
      patches = [ ];
      npmDepsHash = "sha256-hqYzdp1FwPhYkBP278fQXgY9NCKB6Q3P6Gko7BfP0m0=";
      # Its fixture is the disabled, network-bound test-download-model.
      disabledTests = old.disabledTests ++ [ "test-llama-context-model" ];
    });
  });
  unearth-vicinae = final.callPackage ../pkgs/unearth/vicinae { };
  zsh-share-only = final.runCommand "zsh-share-only" { } /* bash */ ''
    mkdir --parents "$out/share"
    ln --symbolic ${final.zsh}/share/zsh "$out/share/zsh"
  '';
}
