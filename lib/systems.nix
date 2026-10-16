{ self }:
{
  systems.nixosHost =
    { inputs, flake }:
    host:
    self.nixosSystem {
      inherit (host) system;

      specialArgs = { inherit host inputs; };

      modules = [
        ../system/configuration.nix
        host.module
        inputs.home-manager.nixosModules.home-manager

        {
          nixpkgs.overlays = self.overlays.forHost { inherit inputs host; };

          home-manager.useGlobalPkgs = true;
          home-manager.useUserPackages = true;
          home-manager.backupFileExtension = "bak";
          home-manager.sharedModules = [ inputs.spicetify-nix.homeManagerModules.spicetify ];
          home-manager.users.kevin = import ../home;
          home-manager.extraSpecialArgs = {
            dotfilesPath = flake;
            inherit host;
          };
        }
      ];
    };
}
