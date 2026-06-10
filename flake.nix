{
  description = "Kevin's NixOS configuration";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nixpkgs-claude.url = "github:NixOS/nixpkgs/master";
    nixpkgs-stable.url = "github:NixOS/nixpkgs/nixos-25.05";
    home-manager = {
      url = "github:nix-community/home-manager/master";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    hyprland.url = "github:hyprwm/Hyprland";
    hyprland-plugins = {
      url = "github:hyprwm/hyprland-plugins";
      inputs.hyprland.follows = "hyprland";
    };
    hyprqt6engine = {
      url = "github:hyprwm/hyprqt6engine";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    vicinae.url = "github:vicinaehq/vicinae";
  };

  outputs = { self, nixpkgs, nixpkgs-claude, nixpkgs-stable, home-manager, hyprland, hyprland-plugins, hyprqt6engine, vicinae, ... }:
  let
    system = "x86_64-linux";
    localPackagesOverlay = import ./overlays/local-packages.nix;
    claudeCodeOverlay = final: prev:
      let
        claudePkgs = import nixpkgs-claude {
          system = final.stdenv.hostPlatform.system;
          config.allowUnfreePredicate = pkg:
            builtins.elem (nixpkgs-claude.lib.getName pkg) [ "claude-code" ];
        };
      in {
        claude-code = claudePkgs.claude-code;
      };
    sharedInputs = {
      inherit
        nixpkgs
        nixpkgs-claude
        nixpkgs-stable
        home-manager
        hyprland
        hyprland-plugins
        hyprqt6engine
        vicinae
        ;
    };
    hosts = {
      laptop = {
        name = "laptop";
        isPhysical = true;
        hyprland = {
          autostartHost = "hosts/laptop/autostart.conf";
          inputDevices = "hosts/laptop/input-devices.conf";
          monitors = "hosts/laptop/monitors.conf";
          env = "config/hypr/env.conf";
        };
      };
      desktop = {
        name = "desktop";
        isPhysical = true;
        hyprland = {
          autostartHost = "hosts/desktop/autostart.conf";
          inputDevices = "hosts/desktop/input-devices.conf";
          monitors = "hosts/desktop/monitors.conf";
          env = "hosts/desktop/env.conf";
        };
      };
    };

    # Set to true to rebuild the targeted native-code packages from source with
    # `-O3 -march=native` / `target-cpu=native` instead of using stock cached
    # nixpkgs builds.
    enableNativeOptimizations = true;

    mkHost =
      {
        host,
        hostModule,
        enableHostNativeOptimizations ? enableNativeOptimizations,
      }:
      nixpkgs.lib.nixosSystem {
        inherit system;
        specialArgs = {
          inherit hyprland host;
          enableNativeOptimizations = enableHostNativeOptimizations;
          inputs = sharedInputs;
        };
        modules = [
          ./system/configuration.nix
          hostModule
          home-manager.nixosModules.home-manager
          {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.backupFileExtension = "bak";
            home-manager.users.kevin = import ./home;
            home-manager.extraSpecialArgs = {
              dotfilesPath = self;
              inherit host vicinae;
              inputs = sharedInputs;
              enableNativeOptimizations = enableHostNativeOptimizations;
            };
          }
        ];
      };
  in {
    overlays.default = final: prev:
      localPackagesOverlay final prev // claudeCodeOverlay final prev;

    packages.${system} =
      let
        pkgs = import nixpkgs {
          inherit system;
          config.allowUnfreePredicate = pkg:
            builtins.elem (nixpkgs.lib.getName pkg) [ "claude-code" ];
          overlays = [ self.overlays.default ];
        };
      in {
        inherit (pkgs)
          desktopctl
          helium
          openchamber
          openchamber-backend-mux
          openchamber-claude-bridge
          snappy-switcher
          ;
      };

    nixosConfigurations.laptop = mkHost {
      host = hosts.laptop;
      hostModule = ./hosts/laptop/system.nix;
    };
    nixosConfigurations.desktop = mkHost {
      host = hosts.desktop;
      hostModule = ./hosts/desktop/system.nix;
    };
    devShells.${system}.default = let
      pkgs = import nixpkgs { inherit system; };
    in pkgs.mkShell {
      nativeBuildInputs = with pkgs; [
        cargo
        rustc
        rust-analyzer
        clippy
        rustfmt
        pkg-config
        sqlite
      ];
    };
  };
}
