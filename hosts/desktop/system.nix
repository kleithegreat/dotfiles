{ config, lib, pkgs, ... }:

{
  boot.initrd.availableKernelModules = [ "xhci_pci" "ahci" "nvme" "usbhid" "usb_storage" "sd_mod" ];
  boot.kernel.sysctl = {
    "vm.dirty_ratio" = 10;
    "vm.dirty_background_ratio" = 5;
  };
  # Preserved VRAM must survive suspend, and /tmp is tmpfs; without it resumes garble.
  boot.extraModprobeConfig = ''
    options nvidia NVreg_TemporaryFilePath=/var/tmp
  '';

  fileSystems."/" = {
    device = "/dev/disk/by-uuid/431cdfea-3583-453d-b2dd-9a46d01c4a33";
    fsType = "ext4";
  };

  fileSystems."/boot/efi" = {
    device = "/dev/disk/by-uuid/ECCF-6FDB";
    fsType = "vfat";
    options = [ "fmask=0077" "dmask=0077" "noauto" "x-systemd.automount" ];
  };

  fileSystems."/mnt/shared" = {
    device = "/dev/disk/by-uuid/426244fd-2b88-4eae-81fe-3466fc631d43";
    fsType = "ext4";
    options = [ "nofail" "x-systemd.device-timeout=10s" ];
  };

  systemd.services.power-profiles-daemon.postStart = /* bash */ ''
    ${lib.getExe' config.services.power-profiles-daemon.package "powerprofilesctl"} set performance
  '';

  hardware.graphics.enable = true;
  hardware.nvidia = {
    modesetting.enable = true;
    open = true;
    powerManagement.enable = true;
    # Held until the resume validation in TODO.md passes.
    powerManagement.kernelSuspendNotifier = false;
  };
  services.xserver.videoDrivers = [ "nvidia" ];

  # Freezing user sessions on suspend black-screens resume (nixpkgs #371058).
  systemd.services.systemd-suspend.environment.SYSTEMD_SLEEP_FREEZE_USER_SESSIONS = "false";

  environment.sessionVariables.__EGL_VENDOR_LIBRARY_FILENAMES =
    "/run/opengl-driver/share/glvnd/egl_vendor.d/10_nvidia.json:/run/opengl-driver/share/glvnd/egl_vendor.d/50_mesa.json";

  # ── GPU fans ──────────────────────────────────────────────────
  services.lact.enable = true;
  # Not `services.lact.settings`: lactd needs integer curve keys, which it can only emit as strings.
  environment.etc."lact/config.yaml".text = /* yaml */ ''
    version: 7
    daemon:
      log_level: info
      admin_group: wheel
    gpus:
      10DE:2206-10DE:1467-0000:01:00.0:
        fan_control_enabled: true
        fan_control_settings:
          mode: curve
          static_speed: 1.0
          temperature_key: GPU
          interval_ms: 500
          curve:
            50: 0.50
            60: 0.65
            70: 0.85
            75: 1.0
          spindown_delay_ms: 5000
          change_threshold: 2
          # Manual mode can't stop the fans; below this the vBIOS's zero-RPM idle takes over.
          auto_threshold: 45
  '';
  systemd.services.lactd.restartTriggers = [ config.environment.etc."lact/config.yaml".source ];

  # ── Location ──────────────────────────────────────────────────
  # Stationary: pinned, not geolocated (docs/sun-schedule.md). Ithaca, NY.
  time.timeZone = "America/New_York";
  environment.sessionVariables.DESKTOPCTL_LOCATION = "42.4440,-76.5019";

  # ── Heater ────────────────────────────────────────────────────
  # Wanted by nothing: the shell's Power pane starts and stops it. Both miners
  # pay this Kryptex account, which holds earnings as BTC.
  systemd.user.targets.heater.description = "Mine on the GPU and every core as a space heater";
  systemd.user.services = let
    account = "kevvinlei89@gmail.com/%H";
  in {
    heater-gpu = {
      description = "Mine Pearl on the GPU";
      partOf = [ "heater.target" ];
      requiredBy = [ "heater.target" ];
      serviceConfig = {
        # Compute-bound on purpose: a DAG coin fills the 10 GB card and starves the desktop of VRAM.
        # Without a TTY it prints nothing; the log file is the journal's only feed.
        ExecStart = "${lib.getExe pkgs.srbminer} --disable-cpu --algorithm pearlhash --pool prl-us.kryptex.network:7048 --wallet ${account} --log-file /dev/stdout";
        # Autotune results and compiled kernels land in the working directory.
        StateDirectory = "heater";
        WorkingDirectory = "%S/heater";
        Restart = "on-failure";
        RestartSec = 30;
      };
    };
    heater-cpu = {
      description = "Mine Monero on every core";
      partOf = [ "heater.target" ];
      requiredBy = [ "heater.target" ];
      serviceConfig = {
        ExecStart = "${lib.getExe pkgs.xmrig} --coin=XMR --url=xmr-us.kryptex.network:7029 --user=${account} --no-color";
        CPUSchedulingPolicy = "idle";
        Restart = "on-failure";
        RestartSec = 30;
      };
    };
  };

  # ── Homelab compute ───────────────────────────────────────────
  # An agent of the homelab cluster only while sweeps run (docs/homelab-agent.md).
  services.k3s = {
    enable = true;
    role = "agent";
    serverAddr = "https://k8s-api.home.lab:6443";
    tokenFile = "/etc/k3s/join-token";
    nodeIP = "192.168.8.131";
    nodeTaint = [ "moneymachine/batch=true:NoSchedule" ];
    extraFlags = [ "--flannel-iface=enp4s0" ];
  };
  systemd.services.k3s = {
    wantedBy = lib.mkForce [ ];
    # kubelet mounts the NFS volumes below for pods scheduled here.
    path = [ pkgs.nfs-utils ];
    # Stopping k3s alone leaves every container running.
    serviceConfig.ExecStopPost = "${config.services.k3s.package}/bin/k3s-killall.sh";
  };
  # The Jobs' only data path: inputs read-only, results read-write, every client squashed to kevin.
  services.nfs.server = {
    enable = true;
    exports = let
      nodes = [ "192.168.8.131" "192.168.8.153" "192.168.8.222" "192.168.8.229" ];
      opts = mode: lib.concatMapStringsSep " " (n: "${n}(${mode},all_squash,anonuid=1000,anongid=100,no_subtree_check)") nodes;
    in ''
      /srv/moneymachine/inputs ${opts "ro"}
      /srv/moneymachine/results ${opts "rw"}
    '';
  };
  systemd.tmpfiles.rules = [
    "d /srv/moneymachine/inputs 0755 kevin users -"
    "d /srv/moneymachine/results 0755 kevin users -"
  ];
  security.polkit.extraConfig = /* javascript */ ''
    polkit.addRule(function(action, subject) {
      if (action.id === "org.freedesktop.systemd1.manage-units" &&
          action.lookup("unit") === "k3s.service" &&
          ["start", "stop"].indexOf(action.lookup("verb")) >= 0 &&
          subject.user === "kevin") {
        return polkit.Result.YES;
      }
    });
  '';
  networking.firewall.extraInputRules = ''
    ip saddr { 192.168.8.153, 192.168.8.222, 192.168.8.229 } udp dport 8472 accept
    ip saddr { 192.168.8.153, 192.168.8.222, 192.168.8.229, 10.42.0.0/16 } tcp dport { 9100, 10250 } accept
    ip saddr { 192.168.8.153, 192.168.8.222, 192.168.8.229 } tcp dport 2049 accept
  '';
  # Its 192.168.8.0/24 subnet route would carry the wired LAN through the Brume.
  services.tailscale.extraSetFlags = [ "--accept-routes=false" ];

  environment.systemPackages = [ pkgs.macos-vm ];
}
