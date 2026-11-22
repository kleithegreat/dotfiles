{ inputs }:

final: prev: {
  bend2-lsp = final.callPackage ../pkgs/bend2-lsp { };
  bambu-studio = final.callPackage ../pkgs/bambu-studio {
    upstreamBambuStudio = prev.bambu-studio;
  };
  comfyui = final.callPackage ../pkgs/comfyui { };
  ctx = final.callPackage ../pkgs/ctx { };
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
  desktopctl = final.callPackage ../desktopctl {
    inherit (inputs) owly;
    craneLib = inputs.crane.mkLib final;
  };
  helium = final.callPackage ../pkgs/helium { };
  kernel-oom-notifier = final.callPackage ../pkgs/kernel-oom-notifier { };
  laptop-panel-edid = final.callPackage ../pkgs/laptop-panel-edid { };
  linux-devmgmt = final.callPackage ../pkgs/linux-devmgmt { };
  lmstudio = final.callPackage ../pkgs/lmstudio {
    upstreamLmstudio = prev.lmstudio;
  };
  macos-vm = final.callPackage ../pkgs/macos-vm { };
  neuwaita = final.callPackage ../pkgs/neuwaita { };
  qemu-reims-vgpu = final.callPackage ../pkgs/qemu-reims-vgpu { };
  srbminer = final.callPackage ../pkgs/srbminer { };
  # kdePackages.sddm wraps this scope's sddm; the patch keeps a greeter after TerminateSession (docs/hyprland.md).
  qt6Packages = prev.qt6Packages.overrideScope (qfinal: qprev: {
    sddm-unwrapped = qprev.sddm-unwrapped.overrideAttrs (old: {
      patches = (old.patches or [ ]) ++ [ ../patches/sddm/sddm-helper-signal-is-not-auth-error.patch ];
    });
  });
  reims-vgpu = final.callPackage ../pkgs/reims-vgpu { };
  sddm-theme = final.callPackage ../pkgs/sddm-theme { };
  sf-pro = final.callPackage ../pkgs/sf-pro { };
  snappy-switcher = final.callPackage ../pkgs/snappy-switcher { };
  tree-sitter-bend2 = final.callPackage ../pkgs/tree-sitter-bend2 { };
  zsh-share-only = final.runCommand "zsh-share-only" { } /* bash */ ''
    mkdir --parents "$out/share"
    ln --symbolic ${final.zsh}/share/zsh "$out/share/zsh"
  '';
}
