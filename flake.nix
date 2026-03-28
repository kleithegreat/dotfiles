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
  };

  outputs = { self, nixpkgs, home-manager, hyprland, hyprland-plugins, hyprqt6engine, vicinae, snappy-switcher, ... }:
  let
    mkHost = hostName: hostModule: nixpkgs.lib.nixosSystem {
      specialArgs = {
        inherit hyprland hostName;
        inputs = { inherit nixpkgs hyprland hyprland-plugins hyprqt6engine vicinae snappy-switcher home-manager; };
      };
      modules = [
        { nixpkgs.hostPlatform = "x86_64-linux"; }
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
            inherit hostName hyprland hyprland-plugins hyprqt6engine vicinae snappy-switcher;
          };
        }
      ];
    };
  in {
    nixosConfigurations.vm = mkHost "vm" ./hosts/vm/system.nix;
    nixosConfigurations.laptop = mkHost "laptop" ./hosts/laptop/system.nix;
    nixosConfigurations.desktop = mkHost "desktop" ./hosts/desktop/system.nix;
  };
}
