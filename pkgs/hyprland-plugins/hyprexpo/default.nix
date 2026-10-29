{
  fetchFromGitHub,
  lib,
  hyprland,
  hyprlandPlugins,
}:

hyprlandPlugins.mkHyprlandPlugin {
  pluginName = "hyprexpo";
  version = "0.56.2+5-unstable-2026-10-25";

  src = fetchFromGitHub {
    owner = "sandwichfarm";
    repo = "hyprexpo";
    rev = "62fc27b8d6e0ff2eb0b97fa0568a91ad5d4239d2";
    hash = "sha256-MZVppHnAAeUBGYnbW6vMS2tYyZqnjgLx8l0mUfjZb5Q=";
  };

  inherit (hyprland) nativeBuildInputs;

  meta = {
    homepage = "https://github.com/sandwichfarm/hyprexpo";
    description = "Maintained Hyprexpo fork with keyboard selection, labels, and gaps";
    license = lib.licenses.bsd3;
    platforms = lib.platforms.linux;
  };
}
