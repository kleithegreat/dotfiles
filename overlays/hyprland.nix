# Hyprland comes from its own flake input rather than nixpkgs, and every piece
# of it — compositor, portal, plugins — has to be built against the same
# patched compositor or the plugin ABI check rejects it at load time. Keeping
# the set namespaced under `hypr` rather than shadowing `pkgs.hyprland` is the
# same reasoning as `pkgs.optimized`: no unrelated dependant gets rebuilt.
{ inputs }:

final: _prev:
let
  system = final.stdenv.hostPlatform.system;

  appendPatches = patches: drv:
    drv.overrideAttrs (old: {
      patches = (old.patches or []) ++ patches;
    });

  guiutils =
    inputs.hyprland.inputs.hyprland-guiutils.packages.${system}.hyprland-guiutils.overrideAttrs (old: {
      buildInputs = (old.buildInputs or []) ++ [ final.pango ];
      preConfigure = (old.preConfigure or "") + ''
        export NIX_CFLAGS_COMPILE="$NIX_CFLAGS_COMPILE $(pkg-config --cflags pango)"
      '';
    });

  # Hyprland 0.56.2 asks for `find_package(glaze 7...<8)` while nixpkgs has
  # moved on to glaze 8, so CMake falls back to fetching glaze v7.2.0 over the
  # network and dies in the sandbox. Keep a 7.x around for Hyprland only,
  # mirroring the SSL/interop toggles from the flake's own glaze-hyprland
  # overlay. Drop once the Hyprland input carries upstream's unbounded
  # find_package.
  glazeVersion = "7.9.1";
  glaze =
    (final.glaze.override {
      enableSSL = false;
      enableInterop = false;
    }).overrideAttrs (_: {
      version = glazeVersion;
      src = final.fetchFromGitHub {
        owner = "stephenberry";
        repo = "glaze";
        tag = "v${glazeVersion}";
        hash = "sha256-NRRq5MGF2f5PW0teYnq58ELzson+U6KHVPaY6r30KLA=";
      };
    });

  hyprland = final.optimize.cc (
    appendPatches [
      ../patches/hyprland/hyprland-floating-top-decoration-rounding-0.55.patch
      ../patches/hyprland/hyprland-gcc15-designated-initializer-fix-0.55.patch
    ] (inputs.hyprland.packages.${system}.hyprland.override {
      hyprland-guiutils = guiutils;
      glaze-hyprland = glaze;
    })
  );

  pluginHelpers = final.callPackage
    "${inputs.nixpkgs}/pkgs/applications/window-managers/hyprwm/hyprland-plugins/default.nix"
    {
      inherit hyprland;
    };

  upstreamPlugins = inputs.hyprland-plugins.packages.${system};
in
{
  hypr = {
    inherit hyprland;

    portal = final.optimize.cc (
      inputs.hyprland.packages.${system}.xdg-desktop-portal-hyprland.override {
        inherit hyprland;
      }
    );

    pluginDir = final.symlinkJoin {
      name = "hyprland-plugins";
      paths = [
        (final.optimize.cc (upstreamPlugins.hyprbars.override {
          inherit hyprland;
          hyprlandPlugins = pluginHelpers;
        }))
        (final.optimize.cc (final.callPackage ../pkgs/hyprland-plugins/hyprexpo {
          inherit hyprland;
          hyprlandPlugins = pluginHelpers;
        }))
      ];
    };
  };
}
