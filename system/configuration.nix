{ lib, pkgs, host, inputs, ... }:

let
  # Every name either host's closure asks the predicate about, grouped by what
  # pulls it in. `cuda_compat` is also asked (an availability probe) and stays
  # refused.
  allowedUnfreePackageNames = [
    # Applications — home.packages
    "bambu-studio"
    "discord"
    "discord-unwrapped"
    "lmstudio"
    "obsidian"
    "slack"
    "spotify"
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

    # CUDA userspace — comfyui -> torch, gpu-burn
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
  ];

  boot.tmp.useTmpfs = true;

  nix.settings = {
    experimental-features = [ "nix-command" "flakes" "pipe-operators" ];
    # Lets the flake's own `nixConfig` block apply; without it nix ignores
    # every setting there as untrusted.
    trusted-users = [ "root" "@wheel" ];
    system-features = lib.mkIf pkgs.optimize.enabled (lib.mkAfter [ pkgs.optimize.hostFeature ]);
    substituters = [
      "https://cache.nixos.org"
    ];
    trusted-public-keys = [
      "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
    ];
    auto-optimise-store = true;
  };
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 30d";
  };
  nix.registry = {
    nixpkgs.flake = inputs.nixpkgs;
    hyprland.flake = inputs.hyprland;
  };
  # Home Manager reuses the system package set in this flake, so keep the
  # unfree allowlist on the shared `pkgs` instance rather than duplicating it
  # in multiple module layers.
  nixpkgs.config.allowUnfreePredicate = pkg:
    builtins.elem (lib.getName pkg) allowedUnfreePackageNames;
  # Both hosts are sm_86. Widening this OOMs libnvshmem (see docs/nix.md); add
  # a capability only when a host actually gets a different GPU.
  nixpkgs.config.cudaCapabilities = [ "8.6" ];
  # ── Networking ───────────────────────────────────────────────
  networking.hostName = host.name;
  networking.networkmanager.enable = true;

  # ── Hyprland ─────────────────────────────────────────────────
  programs.hyprland = {
    enable = true;
    package = pkgs.hypr.hyprland;
    portalPackage = pkgs.hypr.portal;
  };

  # hyprlock — also auto-creates security.pam.services.hyprlock
  programs.hyprlock.enable = true;
  # hyprlock's module runs hypridle as a user unit; hypridle.conf calls desktopctl.
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
    # Most panels are standard RGB and SF Pro looks noticeably softer with the
    # default grayscale-only stack.
    subpixel.rgba = "rgb";
    localConf = ''
  <?xml version='1.0'?>
  <!DOCTYPE fontconfig SYSTEM 'urn:fontconfig:fonts.dtd'>
  <fontconfig>
    <!-- Prefer the small-text optical cut when apps request the generic
         SF Pro family; otherwise fontconfig resolves to Apple's catch-all
         variable face first. -->
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

  # ── Session variables ────────────────────────────────────────
  # Electron apps: use Wayland backend
  environment.sessionVariables.NIXOS_OZONE_WL = "1";
  environment.sessionVariables.HYPR_PLUGIN_DIR = pkgs.hypr.pluginDir;

  # ── Man pages ────────────────────────────────────────────────
  documentation.dev.enable = true;  # development man pages

  # ── Locale ───────────────────────────────────────────────────
  # Timezone is per-host: the laptop tracks it via GeoClue, the desktop pins
  # it. Locale and keyboard defaults stay US English everywhere.
  i18n.defaultLocale = "en_US.UTF-8";
  i18n.extraLocaleSettings = {
    LC_ADDRESS        = "en_US.UTF-8";
    LC_IDENTIFICATION = "en_US.UTF-8";
    LC_MEASUREMENT    = "en_US.UTF-8";
    LC_MONETARY       = "en_US.UTF-8";
    LC_NAME           = "en_US.UTF-8";
    LC_NUMERIC        = "en_US.UTF-8";
    LC_PAPER          = "en_US.UTF-8";
    LC_TELEPHONE      = "en_US.UTF-8";
    LC_TIME           = "en_US.UTF-8";
  };

  # ── System packages (bare minimum — user tools go in home-manager) ──
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
