{ self }:
{
  # Builds one `nixosConfigurations` entry from a host attrset. Everything the
  # modules need is reachable through `pkgs` (via the host's overlays) or the
  # `host` special argument; nothing else is threaded in.
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
          home-manager.users.kevin = import ../home;
          home-manager.extraSpecialArgs = {
            dotfilesPath = flake;
            inherit host inputs;
          };
        }
      ];
    };
}
