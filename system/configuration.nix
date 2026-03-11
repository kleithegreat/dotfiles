{ config, pkgs, ... }:

{
  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  nixpkgs.config.allowUnfree = true;

  # ── Networking ───────────────────────────────────────────────
  networking.hostName = "nixos";
  networking.networkmanager.enable = true;
  # firewall: allow Samba and mDNS; add more as needed
  networking.firewall = {
    enable = true;
    allowedTCPPorts = [ 445 139 ];
    allowedTCPPortRanges = [{ from = 1714; to = 1764; }];  # KDE Connect
    allowedUDPPorts = [ 137 138 5353 ];
    allowedUDPPortRanges = [{ from = 1714; to = 1764; }];  # KDE Connect
  };

  # ── Hyprland ─────────────────────────────────────────────────
  programs.hyprland = {
    enable = true;
    xwayland.enable = true;
  };

  # hyprlock — also auto-creates security.pam.services.hyprlock
  programs.hyprlock.enable = true;

  # ── Captive Portal Browser ──────────────────────────────────
  # Dedicated Chromium instance for logging into captive portals
  # (hotel/airport WiFi) without messing with your DNS settings.
  # Uses NetworkManager to auto-detect DNS — just run `captive-browser`.
  programs.captive-browser = {
    enable = true;
    interface = "wlp0s20f3";  # TODO: verify with `ip link show` on your machine
  };

  # ── Fonts ────────────────────────────────────────────────────
  fonts.packages = with pkgs; [
    nerd-fonts.jetbrains-mono
    overpass
    noto-fonts
    noto-fonts-cjk-sans
    noto-fonts-color-emoji
  ];

  # ── Session variables ────────────────────────────────────────
  # Electron apps: use Wayland backend
  environment.sessionVariables.NIXOS_OZONE_WL = "1";
  environment.sessionVariables.__EGL_VENDOR_LIBRARY_FILENAMES =
    "/run/opengl-driver/share/glvnd/egl_vendor.d/50_mesa.json";

  # ── XDG Portals ──────────────────────────────────────────────
  # XDPH for screensharing, GTK as general fallback, KDE for file picker
  # The file picker routing is done via ~/.config/xdg-desktop-portal/portals.conf
  # which is managed by home-manager (see home/default.nix)
  xdg.portal = {
    enable = true;
    extraPortals = with pkgs; [
      xdg-desktop-portal-hyprland
      xdg-desktop-portal-gtk
      kdePackages.xdg-desktop-portal-kde
    ];
  };

  # ── Display manager ──────────────────────────────────────────
  services.displayManager.sddm = {
    enable = true;
    wayland.enable = true;
  };

  # ── UPower (battery info for Quickshell) ────────────────────
  services.upower.enable = true;

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

  # ── Tailscale ────────────────────────────────────────────────
  services.tailscale.enable = true;

  # ── Mullvad VPN ──────────────────────────────────────────────
  services.mullvad-vpn.enable = true;

  # ── Keyring (gnome-keyring — most reliable with SDDM + Hyprland) ──
  services.gnome.gnome-keyring.enable = true;
  security.pam.services.sddm.enableGnomeKeyring = true;
  # For login to auto-unlock the keyring
  security.pam.services.login.enableGnomeKeyring = true;

  # ── dconf (required for GTK settings to persist) ─────────────
  programs.dconf.enable = true;

  # ── Qt theming ───────────────────────────────────────────────
  # qt6ct is set via env var in Hyprland env.conf (QT_QPA_PLATFORMTHEME=qt6ct)
  # The qt6ct package itself is in home-manager packages
  
  # ── Man pages ────────────────────────────────────────────────
  documentation.man.enable = true;
  documentation.dev.enable = true;  # development man pages

  # ── Locale ───────────────────────────────────────────────────
  services.automatic-timezoned.enable = true;
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
    settings.PasswordAuthentication = true;
  };

  # ── System packages (bare minimum — user tools go in home-manager) ──
  environment.systemPackages = with pkgs; [
    vim
    git
    wget
    curl
    cifs-utils       # SMB/CIFS mount support
    libsecret        # Secret Service client lib (for apps to talk to keyring)
    qt6Packages.qt6ct  # Qt6 configuration tool (system-wide so env var works)
  ];

  system.stateVersion = "25.05";
}
