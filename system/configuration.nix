{ config, lib, pkgs, hyprland, host, inputs, enableNativeOptimizations, ... }:

let
  system = pkgs.stdenv.hostPlatform.system;
  hostName = host.name;
  localPackagesOverlay = import ../overlays/local-packages.nix;
  nativeOptimizations = import ./native-optimizations.nix {
    inherit lib host enableNativeOptimizations;
  };
  optimizedPackages = import ../overlays/native-optimized.nix {
    inherit lib inputs host enableNativeOptimizations;
  };
  optimizedPkgs = pkgs.appendOverlays [ optimizedPackages.overlay ];
  appendPatches = patches: drv:
    drv.overrideAttrs (old: {
      patches = (old.patches or []) ++ patches;
    });
  mkPatchedHyprPlugin = plugin: patches:
    nativeOptimizations.optimizeCCPackage (
      appendPatches patches (plugin.override {
        hyprland = patchedHyprland;
        hyprlandPlugins = patchedHyprlandPluginHelpers;
      })
    );

  patchedHyprland = nativeOptimizations.optimizeCCPackage (
    appendPatches [
      ../patches/hyprland/hyprland-floating-top-decoration-rounding-0.54.patch
      ../patches/hyprland/hyprland-gcc15-designated-initializer-fix-0.54.patch
    ] hyprland.packages.${system}.hyprland
  );

  patchedHyprlandPortal = nativeOptimizations.optimizeCCPackage (
    hyprland.packages.${system}.xdg-desktop-portal-hyprland.override {
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
      hyprbars = mkPatchedHyprPlugin upstreamHyprPluginPkgs.hyprbars [
        ../patches/hyprland-plugins/hyprbars-hyprland-0.54.patch
      ];

      hyprexpo = nativeOptimizations.optimizeCCPackage localHyprexpo;
    };
  hyprPluginDir = pkgs.symlinkJoin {
    name = "hyprland-plugins";
    paths = with hyprPluginPkgs; [
      hyprbars
      hyprexpo
    ];
  };

  allowedUnfreePackageNames = [
    "claude-code"
    "cuda_cccl"
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
    "discord"
    "libcublas"
    "libcufft"
    "libcurand"
    "libcusolver"
    "libcusparse"
    "libnpp"
    "libnvjitlink"
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
    "unrar"
    "vscode"
    "zoom"
  ];
in
{
  imports = [
    (import ./physical-host.nix {
      inherit config lib pkgs host;
    })
    (import ./qt.nix {
      inherit lib pkgs inputs host enableNativeOptimizations;
    })
    (import ./users.nix {
      inherit pkgs;
    })
    (import ./services.nix {
      inherit pkgs optimizedPkgs patchedHyprlandPortal;
    })
  ];

  config = lib.mkMerge [
    {
      boot.tmp.useTmpfs = true;

      nix.settings = {
        experimental-features = [ "nix-command" "flakes" ];
        system-features = lib.mkIf enableNativeOptimizations (lib.mkAfter [ nativeOptimizations.hostFeature ]);
        substituters = [
          "https://cache.nixos.org"
          "https://hyprland.cachix.org"
          "https://vicinae.cachix.org"
        ];
        trusted-public-keys = [
          "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
          "hyprland.cachix.org-1:a7pgxzMz7+chwVL3/pzj6jIBMioiJM7ypFP8PwtkuGc="
          "vicinae.cachix.org-1:1kDrfienkGHPYbkpNj1mWTr7Fm1+zcenzgTizIcI3oc="
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
        vicinae.flake = inputs.vicinae;
      };
      # Home Manager reuses the system package set in this flake, so keep the
      # unfree allowlist on the shared `pkgs` instance rather than duplicating it
      # in multiple module layers.
      nixpkgs.config.allowUnfreePredicate = pkg:
        builtins.elem (lib.getName pkg) allowedUnfreePackageNames;
      nixpkgs.overlays = [ localPackagesOverlay ];

      # ── Networking ───────────────────────────────────────────────
      networking.hostName = hostName;
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
