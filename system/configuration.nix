{ config, lib, pkgs, hyprland, hostName, inputs, march, enableMarchOptimizations, ... }:

let
  system = pkgs.stdenv.hostPlatform.system;
  claudeCodeOverlay = import ../overlays/claude-code.nix;
  localPackagesOverlay = import ../overlays/local-packages.nix;
  optimizedPackages = import ../overlays/march-optimized.nix {
    inherit lib inputs march enableMarchOptimizations;
  };
  hyprlandNativeCFlags = [
    "-O3"
    "-march=native"
  ];

  joinFlags =
    flags:
    lib.concatStringsSep " " (lib.filter (flag: flag != null && flag != "") flags);

  optimizeHyprlandNativePackage =
    drv:
    drv.overrideAttrs (
      old:
      let
        oldEnv = old.env or { };
        existingFlags =
          if builtins.hasAttr "NIX_CFLAGS_COMPILE" oldEnv then
            toString oldEnv.NIX_CFLAGS_COMPILE
          else if builtins.hasAttr "NIX_CFLAGS_COMPILE" old then
            toString old.NIX_CFLAGS_COMPILE
          else
            null;
      in
      {
        env = oldEnv // {
          NIX_CFLAGS_COMPILE = joinFlags [
            existingFlags
            (joinFlags hyprlandNativeCFlags)
          ];
        };
      }
    );

  hyprqt6engine = inputs.hyprqt6engine.packages.${system}.default.overrideAttrs (old: {
    buildInputs = (old.buildInputs or []) ++ [
      pkgs.kdePackages.kcolorscheme
      pkgs.kdePackages.kconfig
      pkgs.kdePackages.kiconthemes
    ];
  });

  patchedHyprland = optimizeHyprlandNativePackage (
    hyprland.packages.${system}.hyprland.overrideAttrs (old: {
      patches = (old.patches or []) ++ [
        ../patches/hyprland/hyprland-floating-top-decoration-rounding-0.54.patch
        ../patches/hyprland/hyprland-gcc15-designated-initializer-fix-0.54.patch
      ];
    })
  );

  patchedHyprlandPortal = optimizeHyprlandNativePackage (
    hyprland.packages.${system}.xdg-desktop-portal-hyprland.override {
      hyprland = patchedHyprland;
    }
  );

  hyprPluginPkgs =
    let
      upstreamHyprPluginPkgs = inputs.hyprland-plugins.packages.${system};
    in
    upstreamHyprPluginPkgs
    // {
      hyprbars = optimizeHyprlandNativePackage (
        (upstreamHyprPluginPkgs.hyprbars.override {
          hyprland = patchedHyprland;
        }).overrideAttrs (old: {
          patches = (old.patches or []) ++ [
            ../patches/hyprland-plugins/hyprbars-hyprland-0.54.patch
          ];
        })
      );

      hyprexpo = optimizeHyprlandNativePackage (
        (upstreamHyprPluginPkgs.hyprexpo.override {
          hyprland = patchedHyprland;
        }).overrideAttrs (old: {
          patches = (old.patches or []) ++ [
            ../patches/hyprland-plugins/hyprexpo-hyprland-0.54.patch
          ];
        })
      );
    };
  hyprPluginDir = pkgs.symlinkJoin {
    name = "hyprland-plugins";
    paths = with hyprPluginPkgs; [
      hyprbars
      hyprexpo
    ];
  };

  sddm-theme = pkgs.where-is-my-sddm-theme.override {
    themeConfig.General = {
      backgroundMode = "fill";
      basicTextColor = "#ebdbb2";
      # Password field
      passwordCharacter = "*";
      passwordFontSize = 36;
      passwordInputBackground = "#3c3836";
      passwordInputRadius = 8;
      passwordInputWidth = 0.25;
      passwordCursorColor = "#ebdbb2";
      passwordMask = true;
      passwordInputCursorVisible = true;
      # User label
      showUsersByDefault = true;
      showUserRealNameByDefault = true;
      usersFontSize = 24;
      # Session label
      showSessionsByDefault = false;
      sessionsFontSize = 16;
    };
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
    ./distributed-builds.nix
  ];

  boot.tmp.useTmpfs = true;

  nix.settings = {
    experimental-features = [ "nix-command" "flakes" ];
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
  nixpkgs.overlays = [
    claudeCodeOverlay
    localPackagesOverlay
    optimizedPackages.overlay
  ];

  # ── Networking ───────────────────────────────────────────────
  networking.hostName = hostName;
  networking.networkmanager.enable = true;

  # ── PKI / TLS trust ────────────────────────────────────────
  security.pki.certificateFiles = [
    ../certs/caddy-root-ca.crt
  ];
  # firewall: mDNS + KDE Connect (Samba ports handled by services.samba.openFirewall)
  networking.firewall = {
    enable = true;
    allowedTCPPortRanges = [{ from = 1714; to = 1764; }];  # KDE Connect
    allowedUDPPorts = [ 5353 ];
    allowedUDPPortRanges = [{ from = 1714; to = 1764; }];  # KDE Connect
  };

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
    inputs.apple-fonts.packages.${system}.sf-pro
    # Quickshell menu fonts without a nixpkgs package in this revision:
    # Berkeley Mono, Outfit (would need custom derivations)
    noto-fonts-cjk-sans
    noto-fonts-color-emoji
    roboto
    dejavu_fonts
    symbola
  ];

  # ── Session variables ────────────────────────────────────────
  # Electron apps: use Wayland backend
  environment.sessionVariables.NIXOS_OZONE_WL = "1";
  environment.sessionVariables.HYPR_PLUGIN_DIR = hyprPluginDir;
  environment.sessionVariables.QT_PLUGIN_PATH = [
    "${hyprqt6engine}/lib/qt-6"
  ];

  # ── XDG Portals ──────────────────────────────────────────────
  # XDPH for screensharing, GTK as general fallback, KDE for file picker
  # The file picker routing is done via ~/.config/xdg-desktop-portal/portals.conf
  # which is managed by home-manager (see home/default.nix)
  xdg.portal = {
    enable = true;
    extraPortals = [
      patchedHyprlandPortal
      pkgs.xdg-desktop-portal-gtk
      pkgs.kdePackages.xdg-desktop-portal-kde
    ];
  };

  # ── Display manager ──────────────────────────────────────────
  services.displayManager.sddm = {
    enable = true;
    wayland.enable = true;
    theme = "where_is_my_sddm_theme";
    extraPackages = [
      sddm-theme
      pkgs.kdePackages.qt5compat
    ];
  };

  # ── UPower (battery info for Quickshell) ────────────────────
  services.upower.enable = true;

  # ── SSD ────────────────────────────────────────────────────
  services.fstrim.enable = true;

  # ── Audio (PipeWire) ─────────────────────────────────────────
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    pulse.enable = true;
    wireplumber.enable = true;
  };
  services.pulseaudio.enable = false;
  security.rtkit.enable = true;  # realtime scheduling for PipeWire

  # ── Bluetooth ────────────────────────────────────────────────
  hardware.bluetooth = {
    enable = true;
    powerOnBoot = true;
    settings.General.Experimental = true;  # battery reporting, fast connect
  };
  services.blueman.enable = true;  # GUI for managing BT devices

  # ── Printing (CUPS) ──────────────────────────────────────────
  services.printing.enable = true;
  services.avahi = {
    enable = true;
    nssmdns4 = true;  # resolve .local mDNS for network printers
    openFirewall = true;
  };

  # ── Samba (client + server for LAN shares) ───────────────────
  services.samba = {
    enable = true;
    openFirewall = true;
    settings = {
      global = {
        workgroup = "WORKGROUP";
        "server string" = "nixos";
        "server role" = "standalone server";
      };
    };
  };
  # ── Docker ───────────────────────────────────────────────────
  virtualisation.docker = {
    enable = true;
    enableOnBoot = false;  # start on-demand, not every boot
  };

  # ── Libvirt / QEMU / Virt-Manager ───────────────────────────
  virtualisation.libvirtd = {
    enable = true;
    qemu = {
      package = pkgs.qemu_kvm;
      swtpm.enable = true;  # TPM emulation for Windows VMs
    };
  };
  programs.virt-manager.enable = true;

  # ── Geolocation ─────────────────────────────────────────────
  services.geoclue2.enable = true;

  # ── Tailscale ────────────────────────────────────────────────
  services.tailscale.enable = true;

  # ── Mullvad VPN ──────────────────────────────────────────────
  services.mullvad-vpn = {
    enable = true;
    package = pkgs.mullvad-vpn;  # default (pkgs.mullvad) is CLI-only; this adds the GUI
  };

  # ── Keyring (gnome-keyring — most reliable with SDDM + Hyprland) ──
  services.gnome.gnome-keyring.enable = true;
  security.pam.services.sddm.enableGnomeKeyring = true;
  security.pam.services.login.enableGnomeKeyring = true;
  # Re-unlock keyring when resuming from hyprlock screen lock
  security.pam.services.hyprlock.enableGnomeKeyring = true;

  # ── GVFS (GUI file manager network browsing) ────────────────
  services.gvfs.enable = true;

  # ── dconf (required for GTK settings to persist) ─────────────
  programs.dconf.enable = true;

  # KDE Partition Manager needs kpmcore's system D-Bus service and polkit
  # action registered outside Home Manager so the privileged helper can start.
  programs.partition-manager.enable = true;

  # ── Qt theming ───────────────────────────────────────────────
  # hyprqt6engine replaces qt6ct as the primary Qt6 platform theme (QT_QPA_PLATFORMTHEME=hyprqt6engine)
  # qt6ct is kept for qt5ct backward compatibility (Qt5 apps still use it)
  
  # ── Man pages ────────────────────────────────────────────────
  documentation.man.enable = true;
  documentation.dev.enable = true;  # development man pages

  # ── Locale ───────────────────────────────────────────────────
  time.timeZone = "America/Chicago";
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

  # ── Shell ────────────────────────────────────────────────────
  programs.zsh.enable = true;

  # ── User ─────────────────────────────────────────────────────
  users.users.kevin = {
    isNormalUser = true;
    extraGroups = [
      "wheel"
      "networkmanager"
      "video"
      "render"
      "docker"        # Docker without sudo
      "libvirtd"      # VM management
      "lp"            # Printing
    ];
    initialPassword = "changeme";
    shell = pkgs.zsh;
  };

  # ── SSH ──────────────────────────────────────────────────────
  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
    };
  };

  # ── System packages (bare minimum — user tools go in home-manager) ──
  environment.systemPackages = with pkgs; [
    vim
    wget
    curl
    cifs-utils       # SMB/CIFS mount support
    ntfs3g           # NTFS read/write (Windows dual-boot)
    dosfstools       # FAT filesystem tools (EFI partitions)
    qt6Packages.qt6ct  # Qt5 configuration tool (kept for qt5ct backward compat)
    hyprqt6engine  # Hyprland-native Qt6 theme engine (with KF6 for full KDE app theming)
    sddm-theme
    bitwarden-desktop  # must be system-level so polkit policy file is linked (nixpkgs#344073)
  ];

  system.stateVersion = "25.05";
}
