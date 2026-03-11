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
  };

  outputs = { self, nixpkgs, home-manager, hyprland, hyprland-plugins, ... }: {
    nixosConfigurations.vm = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      specialArgs = { inherit hyprland; };
      modules = [
        ./system/configuration.nix
        ./hosts/vm/system.nix
        home-manager.nixosModules.home-manager
        {
          home-manager.useGlobalPkgs = true;
          home-manager.useUserPackages = true;
          home-manager.backupFileExtension = "bak";
          home-manager.users.kevin = import ./home;
          home-manager.extraSpecialArgs = {
            dotfilesPath = self;
            hostName = "vm";
            inherit hyprland hyprland-plugins;
          };
        }
      ];
    };

    nixosConfigurations.laptop = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      specialArgs = { inherit hyprland; };
      modules = [
        ./system/configuration.nix
        ./hosts/laptop/system.nix
        home-manager.nixosModules.home-manager
        {
          home-manager.useGlobalPkgs = true;
          home-manager.useUserPackages = true;
          home-manager.backupFileExtension = "bak";
          home-manager.users.kevin = import ./home;
          home-manager.extraSpecialArgs = {
            dotfilesPath = self;
            hostName = "laptop";
            inherit hyprland hyprland-plugins;
          };
        }
      ];
    };
  };
}
