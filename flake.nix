{
  description = "Kevin's NixOS configuration";

  # Honoured only for trusted users; see docs/nix.md before the first rebuild.
  nixConfig = {
    experimental-features = [
      "flakes"
      "nix-command"
      "pipe-operators"
    ];

    http-connections = 50;
    show-trace = true;
    warn-dirty = false;
  };

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nixpkgs-claude.url = "github:NixOS/nixpkgs/master";
    claude-desktop = {
      url = "github:poeck/claude-desktop-nix-flake";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    home-manager = {
      url = "github:nix-community/home-manager/master";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    hyprland = {
      url = "github:hyprwm/Hyprland/v0.57.2";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    hyprland-plugins = {
      url = "github:hyprwm/hyprland-plugins/v0.57.0";
      inputs.hyprland.follows = "hyprland";
    };
    ableton-linux = {
      url = "github:shibco/ableton-linux";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    spicetify-nix = {
      url = "github:Gerg-L/spicetify-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    crane.url = "github:ipetkov/crane";
    owly = {
      # Interim: AX211 concurrent mode ([[airdrop]]).
      url = "github:vale981/owly/83b7c2f6fc0b3c5ad83d72dc48e365e3eb699c62";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    moneymachine = {
      url = "git+file:///home/kevin/repos/moneymachine";
    };
  };

  outputs =
    inputs:
    let
      lib = import ./lib inputs.nixpkgs.lib;

      inherit (lib.attrsets) mapAttrs;

      system = "x86_64-linux";

      hosts = {
        desktop = {
          inherit system;
          isPhysical = true;
          nativeOptimizations = true;
          module = ./hosts/desktop/system.nix;
          hyprland = {
            autostartHost = null;
            inputDevices = "hosts/desktop/input-devices.lua";
            monitors = "hosts/desktop/monitors.lua";
            env = "hosts/desktop/env.lua";
          };
        };

        laptop = {
          inherit system;
          isPhysical = true;
          nativeOptimizations = true;
          module = ./hosts/laptop/system.nix;
          hyprland = {
            autostartHost = "hosts/laptop/autostart.lua";
            inputDevices = "hosts/laptop/input-devices.lua";
            monitors = "hosts/laptop/monitors.lua";
            env = "hosts/laptop/env.lua";
          };
        };
      };
    in
    {
      # Host-independent packages only.
      overlays.default =
        final: prev:
        import ./overlays/local-packages.nix { inherit inputs; } final prev
        // import ./overlays/claude-code.nix { inherit (inputs) nixpkgs-claude; } final prev;

      nixosConfigurations =
        hosts
        |> mapAttrs (
          name: host:
          lib.systems.nixosHost {
            inherit inputs;
            flake = inputs.self;
          } (host // { inherit name; })
        );

      packages.${system} =
        let
          pkgs = import inputs.nixpkgs {
            inherit system;
            overlays = [ inputs.self.overlays.default ];
          };
        in
        {
          inherit (pkgs)
            desktopctl
            helium
            macos-vm
            snappy-switcher
            ;
        };

      devShells.${system}.default =
        let
          pkgs = import inputs.nixpkgs { inherit system; };
        in
        pkgs.mkShell {
          nativeBuildInputs = with pkgs; [
            cargo
            rustc
            rust-analyzer
            clippy
            rustfmt
            pkg-config
            sqlite
          ];
          # desktopctl builds owly-airdrop from the flake's own owly input.
          shellHook = /* bash */ ''
            ln --symbolic --force --no-dereference ${inputs.owly} "$(git rev-parse --show-toplevel)/desktopctl/.owly"
          '';
        };
    };
}
