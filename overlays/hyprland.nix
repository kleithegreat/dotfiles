# Portal and plugins must build against this same patched compositor or the
# plugin ABI check rejects them; namespaced like `pkgs.optimized`.
{ inputs }:

final: _prev:
let
  system = final.stdenv.hostPlatform.system;

  appendPatches = patches: drv:
    drv.overrideAttrs (old: {
      patches = (old.patches or []) ++ patches;
    });

  guiutils =
    (final.optimize.ccache inputs.hyprland.inputs.hyprland-guiutils.packages.${system}.hyprland-guiutils).overrideAttrs (old: {
      buildInputs = (old.buildInputs or []) ++ [ final.pango ];
      preConfigure = (old.preConfigure or "") + ''
        export NIX_CFLAGS_COMPILE="$NIX_CFLAGS_COMPILE $(pkg-config --cflags pango)"
      '';
    });

  # Hyprland 0.56.2 wants glaze 7 and nixpkgs has 8, so CMake would fetch it
  # in the sandbox. Drop once the input's find_package is unbounded.
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
      ../patches/hyprland/hyprland-floating-top-decoration-rounding.patch
      ../patches/hyprland/hyprland-gcc15-designated-initializer-fix.patch
      ../patches/hyprland/hyprland-refocus-stays-on-visible-workspace.patch
    ] (inputs.hyprland.packages.${system}.hyprland.override {
      # security.wrappers needs an ELF to carry cap_sys_nice, not a shell script.
      makeWrapper = final.makeBinaryWrapper;
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
