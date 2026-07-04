{
  fetchFromGitHub,
  lib,
  hyprland,
  hyprlandPlugins,
}:

hyprlandPlugins.mkHyprlandPlugin {
  pluginName = "hyprexpo";
  version = "0.55.4-unstable-2026-07-01";

  src = fetchFromGitHub {
    owner = "sandwichfarm";
    repo = "hyprexpo";
    rev = "e76761b268a0ee1747d41e21355fa315797a9bfd";
    hash = "sha256-sERoTu9NcGD0RA3jAdHc4GOPkRbgqMrgDT8f7+Jv9fc=";
  };

  patches = [
    ../../../patches/hyprland-plugins/hyprexpo-hyprland-0.55.patch
  ];

  inherit (hyprland) nativeBuildInputs;

  meta = {
    homepage = "https://github.com/sandwichfarm/hyprexpo";
    description = "Maintained Hyprexpo fork with keyboard selection, labels, and gaps";
    license = lib.licenses.bsd3;
    platforms = lib.platforms.linux;
  };
}
