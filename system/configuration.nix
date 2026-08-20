{ lib, pkgs, host, inputs, ... }:

let
  system = pkgs.stdenv.hostPlatform.system;
  appendPatches = patches: drv:
    drv.overrideAttrs (old: {
      patches = (old.patches or []) ++ patches;
    });
  mkPatchedHyprPlugin = plugin: patches:
    pkgs.optimize.cc (
      appendPatches patches (plugin.override {
        hyprland = patchedHyprland;
        hyprlandPlugins = patchedHyprlandPluginHelpers;
      })
    );

  patchedHyprlandGuiutils =
    inputs.hyprland.inputs.hyprland-guiutils.packages.${system}.hyprland-guiutils.overrideAttrs (old: {
      buildInputs = (old.buildInputs or []) ++ [ pkgs.pango ];
      preConfigure = (old.preConfigure or "") + ''
        export NIX_CFLAGS_COMPILE="$NIX_CFLAGS_COMPILE $(pkg-config --cflags pango)"
      '';
    });

  # Hyprland 0.56.2 asks for `find_package(glaze 7...<8)` while nixpkgs has
  # moved on to glaze 8, so CMake falls back to fetching glaze v7.2.0 over the
  # network and dies in the sandbox. Keep a 7.x around for Hyprland only,
  # mirroring the SSL/interop toggles from the flake's own glaze-hyprland
  # overlay. Drop once the Hyprland input carries upstream's unbounded
  # find_package.
  glazeForHyprlandVersion = "7.9.1";
  glazeForHyprland =
    (pkgs.glaze.override {
      enableSSL = false;
      enableInterop = false;
    }).overrideAttrs (_: {
      version = glazeForHyprlandVersion;
      src = pkgs.fetchFromGitHub {
        owner = "stephenberry";
        repo = "glaze";
        tag = "v${glazeForHyprlandVersion}";
        hash = "sha256-NRRq5MGF2f5PW0teYnq58ELzson+U6KHVPaY6r30KLA=";
      };
    });

  patchedHyprland = pkgs.optimize.cc (
    appendPatches [
      ../patches/hyprland/hyprland-floating-top-decoration-rounding-0.55.patch
      ../patches/hyprland/hyprland-gcc15-designated-initializer-fix-0.55.patch
    ] (inputs.hyprland.packages.${system}.hyprland.override {
      hyprland-guiutils = patchedHyprlandGuiutils;
      glaze-hyprland = glazeForHyprland;
    })
  );

  patchedHyprlandPortal = pkgs.optimize.cc (
    inputs.hyprland.packages.${system}.xdg-desktop-portal-hyprland.override {
      hyprland = patchedHyprland;
    }
  );

  patchedHyprlandPluginHelpers = pkgs.callPackage
    "${inputs.nixpkgs}/pkgs/applications/window-managers/hyprwm/hyprland-plugins/default.nix"
    {
      hyprland = patchedHyprland;
    };

  hyprPluginPkgs =
    let
      upstreamHyprPluginPkgs = inputs.hyprland-plugins.packages.${system};
      localHyprexpo = pkgs.callPackage ../pkgs/hyprland-plugins/hyprexpo {
        hyprland = patchedHyprland;
        hyprlandPlugins = patchedHyprlandPluginHelpers;
      };
    in
    upstreamHyprPluginPkgs
    // {
      hyprbars = mkPatchedHyprPlugin upstreamHyprPluginPkgs.hyprbars [];

      hyprexpo = pkgs.optimize.cc localHyprexpo;
    };
  hyprPluginDir = pkgs.symlinkJoin {
    name = "hyprland-plugins";
    paths = with hyprPluginPkgs; [
      hyprbars
      hyprexpo
    ];
  };

  allowedUnfreePackageNames = [
    "bambu-studio"
    "cccl"
    "claude-code"
    "cuda-bindings"
    "cuda_cccl"
    "cuda_crt"
    "cuda_cudart"
    "cuda_cuobjdump"
    "cuda_cupti"
    "cuda_cuxxfilt"
    "cuda_gdb"
    "cuda-merged"
    "cuda_nvcc"
    "cuda_nvdisasm"
    "cuda_nvml_dev"
    "cuda_nvprune"
    "cuda_nvrtc"
    "cuda_nvtx"
    "cuda_profiler_api"
    "cuda_sanitizer_api"
    "cudnn"
    "discord"
    "discord-unwrapped"
    "libcublas"
    "libcufft"
    "libcufile"
    "libcurand"
    "libcusolver"
    "libcusparse"
    "libcusparse_lt"
    "libnpp"
    "libnvfatbin"
    "libnvjitlink"
    "libnvshmem"
    "libnvvm"
    "lmstudio"
    "nvidia-settings"
    "nvidia-x11"
    "obsidian"
    "slack"
    "spotify"
    "sf-pro"
    "steam"
    "steam-unwrapped"
    "symbola"
    "torch"
    "triton"
    "unrar"
    "vscode"
    "zoom"
  ];
in
{
  imports = [
    ./physical-host.nix
    ./qt.nix
    ./users.nix
    ./services.nix
  ];

  config = lib.mkMerge [
    {
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
      # Both hosts are sm_86 (laptop RTX 3050 Mobile, desktop RTX 3080), and
      # nothing here is unfree-cached, so every CUDA package is built locally.
      # Left at the nixpkgs default, `cudaCapabilities` spans nine architectures
      # (75 through 121), and source-built CUDA packages compile every device
      # translation unit once per architecture. `libnvshmem` is the one that
      # hurts: it is a full CMake/nvcc build reached through comfyui -> torch,
      # and nine architectures' worth of parallel nvcc exhausts this machine's
      # RAM. Pinning to the capability both hosts actually have cuts that work
      # by ~9x. Add a capability here if a host ever gets a different GPU.
      nixpkgs.config.cudaCapabilities = [ "8.6" ];
      nixpkgs.config.permittedInsecurePackages = [
        # Required by nixpkgs' bitwarden-desktop 2026.6.1 package on this input.
        "electron-39.8.10"
        # Required by nixpkgs' winboat 0.9.0 package on this input.
        "electron-40.10.5"
        "ladybird-0-unstable-2026-06-05"
      ];
      # ── Networking ───────────────────────────────────────────────
      networking.hostName = host.name;
      networking.networkmanager.enable = true;

      # ── Hyprland ─────────────────────────────────────────────────
      programs.hyprland = {
        enable = true;
        xwayland.enable = true;
        package = patchedHyprland;
        portalPackage = patchedHyprlandPortal;
      };

      # hyprlock — also auto-creates security.pam.services.hyprlock
      programs.hyprlock.enable = true;

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
    # Quickshell menu fonts without a nixpkgs package in this revision:
    # Berkeley Mono, Outfit (would need custom derivations)
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
      environment.sessionVariables.HYPR_PLUGIN_DIR = hyprPluginDir;
  
  # ── Man pages ────────────────────────────────────────────────
  documentation.man.enable = true;
  documentation.dev.enable = true;  # development man pages

  # ── Locale ───────────────────────────────────────────────────
  # Timezone is intentionally left dynamic; automatic-timezoned updates it via
  # GeoClue while locale and keyboard defaults stay US English.
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
  console.keyMap = "us";

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
  ];
}
