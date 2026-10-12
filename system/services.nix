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
    # Pre-create the staging dir in world-writable /tmp as kevin-owned 0700 so
    # no other local user can plant a symlink for the root-run sync to follow.
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

        # Must consume the file on every exit, failure included, or the
        # level-triggered path unit spins; see docs/nix.md.
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
    # SDDM opens one greeter window per connected output. Weston's kiosk shell
    # assigns every toplevel to a single output (whichever holds the pointer),
    # so both greeter windows pile onto the laptop panel and the external
    # monitor is left showing nothing but kiosk-shell's black background
    # surface. KWin honours the per-output placement, so each display gets its
    # own correctly-sized greeter.
    wayland.compositor = "kwin";
    theme = "where_is_my_sddm_theme";
    extraPackages = [
      pkgs.sddm-theme
      pkgs.kdePackages.qt5compat
    ];
  };

  services.upower.enable = true;

  # `/boot/efi` is mounted from the Windows NVMe on dual-boot hosts, so the
  # stock `services.fstrim` unit is too broad here. Trim only the Linux root
  # filesystem.
  services.fstrim.enable = false;
  systemd.services.fstrim-root = {
    description = "Discard unused blocks on the Linux root filesystem";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${lib.getExe' pkgs.util-linux "fstrim"} --verbose /";
      PrivateDevices = false;
      PrivateNetwork = true;
      PrivateUsers = false;
      ProtectKernelTunables = true;
      ProtectKernelModules = true;
      ProtectControlGroups = true;
      MemoryDenyWriteExecute = true;
      SystemCallFilter = [ "@default" "@file-system" "@basic-io" "@system-service" ];
    };
  };
  systemd.timers.fstrim-root = {
    description = "Discard unused blocks on the Linux root filesystem once a week";
    wantedBy = [ "timers.target" ];
    unitConfig = {
      ConditionVirtualization = "!container";
      ConditionPathExists = "!/etc/initrd-release";
    };
    timerConfig = {
      OnCalendar = "weekly";
      AccuracySec = "1h";
      Persistent = true;
      RandomizedDelaySec = "100min";
      Unit = "fstrim-root.service";
    };
  };

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
  # `package` is the daemon (`pkgs.mullvad`); the desktop app is `gui.enable`.
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
