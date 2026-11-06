{
  fetchFromGitHub,
  lib,
  hyprland,
  hyprlandPlugins,
}:

hyprlandPlugins.mkHyprlandPlugin {
  pluginName = "hyprexpo";
  version = "0.57.1-unstable-2026-11-05";

  src = fetchFromGitHub {
    owner = "sandwichfarm";
    repo = "hyprexpo";
    rev = "09fef6195555a30da1e81df53413baabdc9593f2";
    hash = "sha256-u3YLwkxBGoUskAi+0s3zmIX0GVsdmsswZ+LJpjLeqF0=";
  };

  inherit (hyprland) nativeBuildInputs;

  meta = {
    homepage = "https://github.com/sandwichfarm/hyprexpo";
    description = "Maintained Hyprexpo fork with keyboard selection, labels, and gaps";
    license = lib.licenses.bsd3;
    platforms = lib.platforms.linux;
  };
}
