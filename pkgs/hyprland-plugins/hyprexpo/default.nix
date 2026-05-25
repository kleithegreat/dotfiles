{
  fetchFromGitHub,
  lib,
  hyprland,
  hyprlandPlugins,
}:

hyprlandPlugins.mkHyprlandPlugin {
  pluginName = "hyprexpo";
  version = "0.1-unstable-2026-05-12";

  src = "${fetchFromGitHub {
    owner = "hyprwm";
    repo = "hyprland-plugins";
    rev = "eaf18d55d51cef00818c5a4fdd4170f8cc2de4dc";
    hash = "sha256-d2wOUZlOqGAW9mwlpq7c/YlneW2ZDJt9d/2bq7mnKdM=";
  }}/hyprexpo";

  patches = [
    ../../../patches/hyprland-plugins/hyprexpo-hyprland-0.54.patch
  ];

  inherit (hyprland) nativeBuildInputs;

  meta = {
    homepage = "https://github.com/hyprwm/hyprland-plugins/tree/eaf18d55d51cef00818c5a4fdd4170f8cc2de4dc/hyprexpo";
    description = "Repo-local Hyprexpo package for the removed Hyprland overview plugin";
    license = lib.licenses.bsd3;
    platforms = lib.platforms.linux;
  };
}
