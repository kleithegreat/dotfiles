{ config, lib, pkgs, host, inputs, ... }:

let
  sccacheDir = "/var/cache/sccache";

  # Exactly what either closure asks about; a CUDA bump that splits out a new
  # package fails evaluation naming it. `cuda_compat` is a probe and stays refused.
  allowedUnfreePackageNames = [
    # Applications — home.packages
    "bambu-studio"
    "claude-desktop"
    "dd-cli"
    "discord"
    "discord-unwrapped"
    "lmstudio"
    "obsidian"
    "slack"
    "spotify"
    "srbminer"
    "unrar"
    "vscode"
    "zoom"

    # Steam
    "steam"
    "steam-unwrapped"

    # Fonts — fonts.packages
    "sf-pro"
    "symbola"

    # NVIDIA driver and tools — hardware.nvidia
    "nvidia-settings"
    "nvidia-x11"

    # CUDA userspace — comfyui -> torch
    "cccl"
    "cuda-bindings"
    "cuda_crt"
    "cuda_cudart"
    "cuda_cupti"
    "cuda_nvcc"
    "cuda_nvml_dev"
    "cuda_nvrtc"
    "cuda_nvtx"
    "cuda_profiler_api"
    "cudnn"
    "libcublas"
    "libcufft"
    "libcufile"
    "libcurand"
    "libcusolver"
    "libcusparse"
    "libcusparse_lt"
    "libnvfatbin"
    "libnvjitlink"
    "libnvshmem"
    "libnvvm"
    "torch"
    "triton"
  ];
in
{
  imports = [
    ./physical-host.nix
    ./qt.nix
    ./users.nix
    ./services.nix
    inputs.owly.nixosModules.default
  ];

  boot.tmp.useTmpfs = true;

  nix.settings = {
    experimental-features = [ "nix-command" "flakes" "pipe-operators" ];
    # Without it nix ignores the flake's `nixConfig` as untrusted.
    trusted-users = [ "root" "@wheel" ];
    system-features = lib.mkIf pkgs.optimize.enabled (lib.mkAfter [ pkgs.optimize.hostFeature ]);
    auto-optimise-store = true;
  };
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 30d";
  };
  services.journald.settings.Journal = {
    SystemMaxUse = "500M";
    MaxRetentionSec = "1month";
  };
  systemd.coredump.settings.Coredump.MaxUse = "1G";
  nix.registry = {
    nixpkgs.flake = inputs.nixpkgs;
    hyprland.flake = inputs.hyprland;
  };
  nixpkgs.config.allowUnfreePredicate = pkg:
    builtins.elem (lib.getName pkg) allowedUnfreePackageNames;
  # Both hosts are sm_86. Widening this OOMs libnvshmem (see docs/nvidia.md); add
  # a capability only when a host actually gets a different GPU.
  nixpkgs.config.cudaCapabilities = [ "8.6" ];

  networking.hostName = host.name;
  networking.networkmanager.enable = true;

  # ── Compiler caches ──────────────────────────────────────────
  programs.ccache.enable = true;
  # Its stats helper wraps a Perl script, which security.wrappers now refuses.
  security.wrappers.nix-ccache.enable = false;
  systemd.tmpfiles.rules = [ "d ${sccacheDir} 0770 root nixbld -" ];
  nix.settings.extra-sandbox-paths = [
    config.programs.ccache.cacheDir
    sccacheDir
  ];
  # Without the sandbox mount (first build, remote builder) both compile uncached rather than fail.
  nixpkgs.overlays = [
    (final: prev: {
      ccacheWrapper = prev.ccacheWrapper.override {
        extraConfig = /* bash */ ''
          export CCACHE_DIR=${config.programs.ccache.cacheDir}
          export CCACHE_UMASK=007
          export CCACHE_MAXSIZE=10G
          [ -w "$CCACHE_DIR" ] || export CCACHE_DISABLE=1
        '';
      };
      sccacheHook =
        let
          # sccache has no umask setting; every nixbld user must be able to write its entries.
          # Never in the hook itself: a group-writable $out makes Nix reject the build.
          sccache = final.writeShellScript "sccache" /* bash */ ''
            umask 007
            exec ${lib.getExe final.sccache} "$@"
          '';
        in
        final.makeSetupHook { name = "sccache-hook"; } (
          final.writeText "sccache-hook.sh" /* bash */ ''
            if [ -w ${sccacheDir} ]; then
              export RUSTC_WRAPPER=${sccache} SCCACHE_DIR=${sccacheDir}
            fi
          ''
        );
    })
  ];

  # ── Hyprland ─────────────────────────────────────────────────
  programs.hyprland = {
    enable = true;
    package = pkgs.hypr.hyprland;
    portalPackage = pkgs.hypr.portal;
  };

  # The session is the Hyprland instance: the kernel closes its event socket
  # however it ends, which ends the anchor and, with it, graphical-session.target.
  systemd.user.services."hyprland-session@" = {
    description = "Hyprland instance %i";
    bindsTo = [ "graphical-session.target" ];
    before = [ "graphical-session.target" ];
    unitConfig.PropagatesStopTo = [ "graphical-session.target" ];
    serviceConfig = {
      ExecStart = "${lib.getExe pkgs.socat} -u UNIX-CONNECT:%t/hypr/%i/.socket2.sock STDOUT";
      StandardOutput = "null";
    };
  };

  programs.hyprlock.enable = true;
  # hypridle.conf calls desktopctl.
  systemd.user.services.hypridle.path = [ pkgs.optimized.desktopctl ];

  # ── Fonts ────────────────────────────────────────────────────
  fonts.packages = with pkgs; [
    nerd-fonts.jetbrains-mono
    nerd-fonts.fira-code
    nerd-fonts.iosevka
    nerd-fonts.recursive-mono
    cozette
    commit-mono
    overpass
    inter
    geist-font
    ibm-plex
    rubik
    noto-fonts
    cantarell-fonts
    source-sans
    sf-pro
    noto-fonts-cjk-sans
    noto-fonts-color-emoji
    roboto
    dejavu_fonts
    symbola
  ];

  fonts.fontconfig = {
    subpixel.rgba = "rgb";
    localConf = ''
  <?xml version='1.0'?>
  <!DOCTYPE fontconfig SYSTEM 'urn:fontconfig:fonts.dtd'>
  <fontconfig>
    <!-- Otherwise generic "SF Pro" resolves to the soft variable catch-all face. -->
    <match target="pattern">
      <test name="family" qual="any">
        <string>SF Pro</string>
      </test>
      <edit name="family" mode="prepend" binding="strong">
        <string>SF Pro Text</string>
      </edit>
    </match>
  </fontconfig>
    '';
  };

  environment.sessionVariables.NIXOS_OZONE_WL = "1";
  environment.sessionVariables.HYPR_PLUGIN_DIR = pkgs.hypr.pluginDir;

  documentation.dev.enable = true;

  # Static on purpose; only the time zone is per host.
  i18n.defaultLocale = "en_US.UTF-8";

  environment.systemPackages = with pkgs; [
    vim
    wget
    curl
    cifs-utils
    ntfs3g
    dosfstools
  ];

  system.stateVersion = "25.05";
}
