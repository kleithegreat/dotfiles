{
  fetchFromGitHub,
  lib,
  hyprland,
  hyprlandPlugins,
}:

hyprlandPlugins.mkHyprlandPlugin {
  pluginName = "hyprexpo";
  version = "0.57.2-unstable-2026-11-10";

  src = fetchFromGitHub {
    owner = "sandwichfarm";
    repo = "hyprexpo";
    rev = "f538f62e17c167eeb2a513998c9c92a648ea30dc";
    hash = "sha256-6RHapQW788rBE2DlNFmfClYZLX65ugr4bT/HV9SJbIc=";
  };

  inherit (hyprland) nativeBuildInputs;

  meta = {
    homepage = "https://github.com/sandwichfarm/hyprexpo";
    description = "Maintained Hyprexpo fork with keyboard selection, labels, and gaps";
    license = lib.licenses.bsd3;
    platforms = lib.platforms.linux;
  };
}
