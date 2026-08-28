{
  description = "Kevin's NixOS configuration";

  # Honoured only for trusted users; `nix.settings.trusted-users` in
  # system/configuration.nix is what grants that. See docs/nix.md for what to
  # pass before the first rebuild that applies either.
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
    home-manager = {
      url = "github:nix-community/home-manager/master";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    hyprland.url = "github:hyprwm/Hyprland/v0.56.2";
    hyprland-plugins = {
      url = "github:hyprwm/hyprland-plugins/v0.56.0";
      inputs.hyprland.follows = "hyprland";
    };
  };

  outputs =
    inputs:
    let
      lib = import ./lib inputs.nixpkgs.lib;

      inherit (lib.attrsets) mapAttrs;

      system = "x86_64-linux";

      # `nativeOptimizations` rebuilds the targeted native-code packages from
      # source with `-O3 -march=native` / `target-cpu=native` instead of using
      # stock cached nixpkgs builds. See overlays/native-optimized.nix.
      hosts = {
        desktop = {
          inherit system;
          isPhysical = true;
          nativeOptimizations = true;
          module = ./hosts/desktop/system.nix;
          hyprland = {
            autostartHost = "hosts/desktop/autostart.lua";
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
      # Host-independent packages only; the native-optimized overlay is applied
      # per host, inside lib/overlays.nix.
      overlays.default =
        final: prev:
        import ./overlays/local-packages.nix final prev
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
        };
    };
}
