{
  description = "Kevin's NixOS configuration";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    home-manager = {
      url = "github:nix-community/home-manager";
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
    snappy-switcher.url = "github:OpalAayan/snappy-switcher";
    opencode.url = "github:sst/opencode";
  };

  outputs = { self, nixpkgs, home-manager, hyprland, hyprland-plugins, hyprqt6engine, vicinae, snappy-switcher, opencode, ... }:
  let
    system = "x86_64-linux";
    sharedInputs = {
      inherit
        nixpkgs
        home-manager
        hyprland
        hyprland-plugins
        hyprqt6engine
        vicinae
        snappy-switcher
        opencode
        ;
    };

    # Set to true to rebuild the targeted native-code packages from source with
    # `-O3 -march=native` / `target-cpu=native` instead of using stock cached
    # nixpkgs builds.
    enableNativeOptimizations = true;

    # Set to true to enable distributed builds, remote builders, and the
    # post-build-hook that pushes paths to the homelab binary cache.
    enableDistributedBuilds = false;

    mkHost =
      {
        hostName,
        hostModule,
        enableHostNativeOptimizations ? enableNativeOptimizations,
      }:
      nixpkgs.lib.nixosSystem {
        inherit system;
        specialArgs = {
          inherit hyprland hostName enableDistributedBuilds;
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
              inherit hostName vicinae snappy-switcher opencode;
              inputs = sharedInputs;
              enableNativeOptimizations = enableHostNativeOptimizations;
            };
          }
        ];
      };
  in {
    overlays.default = import ./overlays/local-packages.nix;

    packages.${system} =
      let
        pkgs = import nixpkgs {
          inherit system;
          overlays = [ self.overlays.default ];
        };
      in {
        inherit (pkgs)
          desktopctl
          helium
          openchamber
          openchamber-claude-bridge
          ;
      };

    nixosConfigurations.vm = mkHost {
      hostName = "vm";
      hostModule = ./hosts/vm/system.nix;
      enableHostNativeOptimizations = false;
    };
    nixosConfigurations.laptop = mkHost {
      hostName = "laptop";
      hostModule = ./hosts/laptop/system.nix;
    };
    nixosConfigurations.desktop = mkHost {
      hostName = "desktop";
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
