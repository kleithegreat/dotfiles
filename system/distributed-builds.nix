{ config, lib, pkgs, hostName, march, enableMarchOptimizations, enableDistributedBuilds, ... }:

let
  defaults = {
    authorizedKeys = [ ];
    connectHosts = {
      desktop = "desktop.local";
      laptop = "laptop.local";
      homelab = "192.168.8.153";
    };
    publicHostKeys = {
      desktop = null;
      laptop = null;
      homelab = null;
    };
    cachePublicKey = null;
    cacheUrl = null;
  };

  data = lib.recursiveUpdate defaults (import ./distributed-builds-data.nix);

  localLanCidr = "192.168.8.0/24";
  builderSshKey = "/root/.ssh/id_ed25519_nix_remote_build";
  hostMarchFeature = lib.optional (enableMarchOptimizations && march != null) "march-${march}";
  cacheUrl =
    if data.cacheUrl != null then data.cacheUrl else "http://${data.connectHosts.homelab}:5000";
  homelabStore = "ssh-ng://nix-ssh@${data.connectHosts.homelab}?ssh-key=${builderSshKey}";

  commonNixosBuilderFeatures = [
    "benchmark"
    "big-parallel"
    "kvm"
    "nixos-test"
  ];

  buildMachinesByHost = {
    desktop = {
      hostName = data.connectHosts.desktop;
      protocol = "ssh-ng";
      sshUser = "nix-ssh";
      sshKey = builderSshKey;
      system = "x86_64-linux";
      # Cap concurrent derivations below raw thread count because these builds
      # already parallelise internally and can be RAM-heavy.
      maxJobs = 2;
      speedFactor = 10;
      supportedFeatures = commonNixosBuilderFeatures ++ lib.optionals enableMarchOptimizations [ "march-rocketlake" ];
      publicHostKey = data.publicHostKeys.desktop;
    };

    laptop = {
      hostName = data.connectHosts.laptop;
      protocol = "ssh-ng";
      sshUser = "nix-ssh";
      sshKey = builderSshKey;
      system = "x86_64-linux";
      maxJobs = 2;
      speedFactor = 20;
      supportedFeatures = commonNixosBuilderFeatures ++ lib.optionals enableMarchOptimizations [ "march-alderlake" ];
      publicHostKey = data.publicHostKeys.laptop;
    };

    homelab = {
      hostName = data.connectHosts.homelab;
      protocol = "ssh-ng";
      sshUser = "nix-ssh";
      sshKey = builderSshKey;
      system = "x86_64-linux";
      # 8 threads and modest free RAM: keep this builder to one derivation at a time.
      maxJobs = 1;
      speedFactor = 4;
      supportedFeatures = [ "benchmark" ];
      publicHostKey = data.publicHostKeys.homelab;
    };
  };

  enableDistributedBuilds' = enableDistributedBuilds && builtins.elem hostName [
    "desktop"
    "laptop"
  ];
in
lib.mkMerge [
  # Advertise host-specific march capabilities only while the optimization
  # overlay is active, so stock nixpkgs derivations stay fully cacheable.
  (lib.mkIf (enableMarchOptimizations && march != null) {
    nix.settings.system-features = lib.mkAfter hostMarchFeature;
  })

  (lib.mkIf enableDistributedBuilds' {
  nix.distributedBuilds = true;
  nix.buildMachines = lib.mapAttrsToList (
    _: machine: machine
  ) (lib.filterAttrs (name: _: name != hostName) buildMachinesByHost);

  nix.settings = {
    builders-use-substitutes = true;
    post-build-hook = "/etc/nix/push-to-homelab-cache.sh";
    substituters = lib.mkAfter [ cacheUrl ];
    trusted-public-keys = lib.mkAfter (lib.optional (data.cachePublicKey != null) data.cachePublicKey);
  };

  environment.etc."nix/push-to-homelab-cache.sh" = {
    mode = "0555";
    text = ''
      #!${pkgs.runtimeShell}
      set -eu

      if [ -z "''${OUT_PATHS:-}" ]; then
        exit 0
      fi

      if ! ${config.nix.package.out}/bin/nix copy --to '${homelabStore}' $OUT_PATHS; then
        echo "warning: failed to push built paths to ${data.connectHosts.homelab}" >&2
      fi
    '';
  };

  # Use the purpose-specific nix-ssh account for remote build traffic on the
  # NixOS machines. The corresponding root-owned client key is generated
  # out-of-band and referenced above via nix.buildMachines.*.sshKey.
  nix.sshServe = {
    enable = true;
    keys = data.authorizedKeys;
    protocol = "ssh-ng";
    trusted = true;
    write = true;
  };

  # The laptop force-disables sshd in its host module. Override that here so it
  # can participate as a remote worker.
  services.openssh.enable = lib.mkOverride 10 true;
  services.openssh.openFirewall = false;

  networking.firewall.extraCommands = lib.mkIf (config.networking.firewall.backend == "iptables") ''
    iptables -A nixos-fw -p tcp -s ${localLanCidr} --dport 22 -j nixos-fw-accept -m comment --comment "LAN nix remote builds"
  '';
  networking.firewall.extraInputRules = lib.mkIf (config.networking.firewall.backend == "nftables") ''
    ip saddr ${localLanCidr} tcp dport 22 accept comment "LAN nix remote builds"
  '';
  networking.firewall.extraStopCommands = lib.mkIf (config.networking.firewall.backend == "iptables") ''
    iptables -D nixos-fw -p tcp -s ${localLanCidr} --dport 22 -j nixos-fw-accept -m comment --comment "LAN nix remote builds" 2>/dev/null || true
  '';
  })
]
