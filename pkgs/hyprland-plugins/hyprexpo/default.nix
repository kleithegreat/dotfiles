{
  fetchFromGitHub,
  lib,
  hyprland,
  hyprlandPlugins,
}:

hyprlandPlugins.mkHyprlandPlugin {
  pluginName = "hyprexpo";
  version = "0.56.2+3-unstable-2026-10-04";

  src = fetchFromGitHub {
    owner = "sandwichfarm";
    repo = "hyprexpo";
    rev = "442e573cf00363af8165341cf1714a581d055dc6";
    hash = "sha256-d1Bnss6Nru4Y7UDhSdWiPSRUjnmFI73lo7WG/PhwFzY=";
  };

  inherit (hyprland) nativeBuildInputs;

  meta = {
    homepage = "https://github.com/sandwichfarm/hyprexpo";
    description = "Maintained Hyprexpo fork with keyboard selection, labels, and gaps";
    license = lib.licenses.bsd3;
    platforms = lib.platforms.linux;
  };
}
