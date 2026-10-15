{ config, lib, pkgs, ... }:

let
  sddmThemeBackgroundDir = pkgs.sddm-theme.backgroundDir;
  sddmThemeBackgroundPath = pkgs.sddm-theme.backgroundPath;
  sddmThemeStagingDir = "/tmp/desktopctl-where-is-my-sddm-theme";
  sddmThemeStagingPath = "${sddmThemeStagingDir}/background";
in
{
  systemd.tmpfiles.rules = [
    "d ${sddmThemeBackgroundDir} 0755 root root - -"
    # kevin-owned 0700 so no other user can plant a symlink for the root-run sync.
    "d ${sddmThemeStagingDir} 0700 kevin kevin - -"
  ];

  system.activationScripts.desktopctlSddmThemeBackground = {
    text = /* bash */ ''
      mkdir --parents "${sddmThemeBackgroundDir}"
      if [ ! -e "${sddmThemeBackgroundPath}" ]; then
        install -D --mode=0644 ${../styling/wallpapers/lmao.png} "${sddmThemeBackgroundPath}"
      fi
    '';
  };

  systemd.services.desktopctl-sddm-theme-sync = {
    description = "Sync desktopctl wallpaper into SDDM background";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = pkgs.writeShellScript "desktopctl-sddm-theme-sync" /* bash */ ''
        set -eu

        if [ ! -f "${sddmThemeStagingPath}" ]; then
          exit 0
        fi

        # Consume on every exit, failure included: PathExists is level-triggered
        # and would respawn this until the start limiter fails both units.
        trap 'rm --force "${sddmThemeStagingPath}"' EXIT

        install -D --mode=0644 "${sddmThemeStagingPath}" "${sddmThemeBackgroundPath}"
      '';
    };
  };

  systemd.paths.desktopctl-sddm-theme-sync = {
    wantedBy = [ "multi-user.target" ];
    pathConfig = {
      PathExists = sddmThemeStagingPath;
      PathChanged = sddmThemeStagingPath;
      Unit = "desktopctl-sddm-theme-sync.service";
    };
  };

  security.pki.certificateFiles = [
    ../certs/homelab-ca.crt
  ];

  networking.firewall = {
    allowedTCPPortRanges = [{ from = 1714; to = 1764; }];
    allowedUDPPorts = [ 5353 ];
    allowedUDPPortRanges = [{ from = 1714; to = 1764; }];
  };

  xdg.portal = {
    enable = true;
    extraPortals = [
      config.programs.hyprland.portalPackage
      pkgs.xdg-desktop-portal-gtk
    ];
    config.common = {
      default = [ "hyprland" "gtk" ];
      "org.freedesktop.impl.portal.FileChooser" = [ "gtk" ];
    };
  };

  services.displayManager.sddm = {
    enable = true;
    wayland.enable = true;
    # Weston's kiosk shell piles every per-output greeter onto one display.
    wayland.compositor = "kwin";
    theme = "where_is_my_sddm_theme";
    extraPackages = [
      pkgs.sddm-theme
      pkgs.kdePackages.qt5compat
    ];
  };

  services.upower.enable = true;

  # The stock unit would also trim the Windows NVMe's EFI partition.
  systemd.services.fstrim.serviceConfig.ExecStart = [
    ""
    "${lib.getExe' pkgs.util-linux "fstrim"} --verbose /"
  ];

  services.pipewire = {
    enable = true;
    package = pkgs.optimized.pipewire;
    alsa.enable = true;
    pulse.enable = true;
    wireplumber = {
      enable = true;
      package = pkgs.optimized.wireplumber;
    };
  };
  security.rtkit.enable = true;

  virtualisation.podman = {
    enable = true;
    dockerCompat = true;
    defaultNetwork.settings.dns_enabled = true;
  };
  virtualisation.libvirtd = {
    enable = true;
    qemu = {
      package = pkgs.qemu_kvm;
      swtpm.enable = true;
    };
  };
  programs.virt-manager.enable = true;

  location.provider = "geoclue2";
  services.geoclue2 = {
    enable = true;
    enableDemoAgent = true;
    appConfig.where-am-i = {
      isAllowed = true;
      isSystem = false;
    };
  };
  # The module's geoclue.conf has no `[ip]` section, which disables the IP source.
  environment.etc."geoclue/conf.d/50-ip.conf".text = lib.generators.toINI { } {
    ip = {
      enable = true;
      method = "ichnaea";
    };
  };
  systemd.services.geoclue.restartTriggers = [
    config.environment.etc."geoclue/conf.d/50-ip.conf".source
  ];
  services.tailscale = {
    enable = true;
    extraSetFlags = [ "--operator=kevin" ];
  };
  services.mullvad-vpn = {
    enable = true;
    gui.enable = true;
  };

  services.gnome.gnome-keyring.enable = true;
  security.pam.services.sddm.enableGnomeKeyring = true;
  security.pam.services.login.enableGnomeKeyring = true;
  security.pam.services.hyprlock.enableGnomeKeyring = true;

  services.gvfs.enable = true;
  programs.dconf.enable = true;
  programs.partition-manager.enable = true;

  environment.systemPackages = [
    pkgs.sddm-theme
    pkgs.bitwarden-desktop
  ];
}
