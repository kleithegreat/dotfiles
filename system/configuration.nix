{ config, lib, pkgs, host, inputs, ... }:

let
  # Exactly what either closure asks for; `cuda_compat` is a probe and stays refused.
  allowedUnfreePackageNames = [
    # Applications — home.packages
    "antigravity-cli"
    "bambu-studio"
    "chatgpt"
    "claude-desktop"
    "copilot-language-server"
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
  # Both hosts are sm_86; widening this OOMs libnvshmem (docs/nvidia.md).
  nixpkgs.config.cudaCapabilities = [ "8.6" ];

  networking.hostName = host.name;
  networking.networkmanager.enable = true;
  # iwlwifi powersave measured 30% loss and up to 1.2s RTT to the first hop on an idle link.
  networking.networkmanager.wifi.powersave = false;

  # ── Hyprland ─────────────────────────────────────────────────
  programs.hyprland = {
    enable = true;
    package = pkgs.hypr.hyprland;
    portalPackage = pkgs.hypr.portal;
  };

  # The kernel closes the event socket however Hyprland ends, which ends the session.
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
