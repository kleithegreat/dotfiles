{ config, lib, pkgs, optimizedPkgs, patchedHyprlandPortal }:

let
  sddmTheme = pkgs.where-is-my-sddm-theme.override {
    themeConfig.General = {
      backgroundMode = "fill";
      basicTextColor = "#ebdbb2";
      passwordCharacter = "*";
      passwordFontSize = 36;
      passwordInputBackground = "#3c3836";
      passwordInputRadius = 8;
      passwordInputWidth = 0.25;
      passwordCursorColor = "#ebdbb2";
      passwordMask = true;
      passwordInputCursorVisible = true;
      showUsersByDefault = true;
      showUserRealNameByDefault = true;
      usersFontSize = 24;
      showSessionsByDefault = false;
      sessionsFontSize = 16;
    }; 
  };
in
{
  security.pki.certificateFiles = [
    ../certs/caddy-root-ca.crt
  ];

  networking.firewall = {
    enable = true;
    allowedTCPPortRanges = [{ from = 1714; to = 1764; }];
    allowedUDPPorts = [ 5353 ];
    allowedUDPPortRanges = [{ from = 1714; to = 1764; }];
  };

  xdg.portal = {
    enable = true;
    extraPortals = [
      patchedHyprlandPortal
      pkgs.xdg-desktop-portal-gtk
      pkgs.kdePackages.xdg-desktop-portal-kde
    ];
  };

  services.displayManager.sddm = {
    enable = true;
    wayland.enable = true;
    theme = "where_is_my_sddm_theme";
    extraPackages = [
      sddmTheme
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
      ExecStart = "${pkgs.util-linux}/sbin/fstrim --verbose /";
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
    package = optimizedPkgs.pipewire;
    alsa.enable = true;
    pulse.enable = true;
    wireplumber = {
      enable = true;
      package = optimizedPkgs.wireplumber;
    };
  };
  services.pulseaudio.enable = false;
  security.rtkit.enable = true;

  hardware.bluetooth = {
    enable = true;
    powerOnBoot = true;
    settings.General.Experimental = true;
  };
  services.blueman.enable = true;

  services.printing.enable = true;
  services.avahi = {
    enable = true;
    nssmdns4 = true;
    openFirewall = true;
  };

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

  virtualisation.docker = {
    enable = true;
    enableOnBoot = false;
  };
  virtualisation.libvirtd = {
    enable = true;
    qemu = {
      package = pkgs.qemu_kvm;
      swtpm.enable = true;
    };
  };
  programs.virt-manager.enable = true;

  services.geoclue2.enable = true;
  services.tailscale = {
    enable = true;
    extraSetFlags = [ "--operator=kevin" ];
  };
  services.mullvad-vpn = {
    enable = true;
    package = pkgs.mullvad-vpn;
  };

  services.gnome.gnome-keyring.enable = true;
  security.pam.services.sddm.enableGnomeKeyring = true;
  security.pam.services.login.enableGnomeKeyring = true;
  security.pam.services.hyprlock.enableGnomeKeyring = true;

  services.gvfs.enable = true;
  programs.dconf.enable = true;
  programs.partition-manager.enable = true;

  environment.systemPackages = [
    pkgs.bitwarden-desktop
  ];
}
