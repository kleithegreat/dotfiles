{
  description = "Kevin's NixOS configuration";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    hyprland.url = "github:hyprwm/Hyprland";
    vicinae = {
      url = "github:vicinaehq/vicinae";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    snappy-switcher.url = "github:OpalAayan/snappy-switcher";
  };

  outputs = { self, nixpkgs, home-manager, hyprland, vicinae, snappy-switcher, ... }:
  let
    mkHost = hostName: hostModule: nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      specialArgs = { inherit hyprland; };
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
            inherit hostName hyprland vicinae snappy-switcher;
          };
        }
      ];
    };
  in {
    nixosConfigurations.vm = mkHost "vm" ./hosts/vm/system.nix;
    nixosConfigurations.laptop = mkHost "laptop" ./hosts/laptop/system.nix;
  };
}
