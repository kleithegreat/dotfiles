final: prev: {
  cantarell-fonts = prev.cantarell-fonts.overrideAttrs (old: {
    # The variable OTF autohint step fails on the current nixpkgs pin; static
    # OTFs preserve the family without depending on that broken target.
    mesonFlags = (old.mesonFlags or []) ++ [
      "-Dbuildvf=false"
      "-Dbuildstatics=true"
    ];
  });

  bambu-studio = final.callPackage ../pkgs/bambu-studio {
    upstreamBambuStudio = prev.bambu-studio;
  };
  comfyui = final.callPackage ../pkgs/comfyui { };
  # Takes the files as real argv and shell-quotes them into the dispatch
  # string: a desktop-entry field code cannot survive it ([[hyprland]]).
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
  desktopctl = final.callPackage ../desktopctl { };
  discord-krisp = final.callPackage ../pkgs/discord-krisp { };
  # Shares comfyui's CUDA set rather than pulling the default one in beside it.
  gpu-burn = prev.gpu-burn.override {
    config = prev.config // { cudaSupport = true; };
    cudaPackages = final.cudaPackages_13_3;
  };
  helium = final.callPackage ../pkgs/helium { };
  kernel-oom-notifier = final.callPackage ../pkgs/kernel-oom-notifier { };
  # `desktopctl` implements the profile switch (desktopctl/src/bin/
  # laptop-power-profile), but arrives through home-manager. Expose just that
  # one binary system-wide: the polkit rule in hosts/laptop/system.nix grants
  # passwordless pkexec by program path, so keeping the privileged entry point
  # in its own package is what stops that grant reaching every other desktopctl
  # subcommand.
  laptop-power-profile = final.runCommand "laptop-power-profile" { } /* bash */ ''
    mkdir --parents "$out/bin"
    ln --symbolic ${final.lib.getExe' final.optimized.desktopctl "laptop-power-profile"} \
      "$out/bin/laptop-power-profile"
  '';
  lmstudio = final.callPackage ../pkgs/lmstudio {
    upstreamLmstudio = prev.lmstudio;
  };
  macos-vm = final.callPackage ../pkgs/macos-vm { };
  neuwaita = final.callPackage ../pkgs/neuwaita { };
  reims-vgpu = final.callPackage ../pkgs/reims-vgpu { };
  sddm-theme = final.callPackage ../pkgs/sddm-theme { };
  sf-pro = final.callPackage ../pkgs/sf-pro { };
  snappy-switcher = final.callPackage ../pkgs/snappy-switcher { };
  zsh-share-only = final.runCommand "zsh-share-only" { } /* bash */ ''
    mkdir --parents "$out/share"
    ln --symbolic ${final.zsh}/share/zsh "$out/share/zsh"
  '';
}
