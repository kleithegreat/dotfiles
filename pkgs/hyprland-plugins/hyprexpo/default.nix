{
  fetchFromGitHub,
  lib,
  hyprland,
  hyprlandPlugins,
}:

hyprlandPlugins.mkHyprlandPlugin {
  pluginName = "hyprexpo";
  version = "0.1-unstable-2026-05-08";

  src = "${fetchFromGitHub {
    owner = "hyprwm";
    repo = "hyprland-plugins";
    rev = "22de29bc1cf4126202df52691d0bc9a065089cba";
    hash = "sha256-hwtKSJcroZ++QAb9rI9L6Sp3XJlDIyWZN7UOVMiN8jY=";
  }}/hyprexpo";

  patches = [
    ../../../patches/hyprland-plugins/hyprexpo-hyprland-0.54.patch
  ];

  inherit (hyprland) nativeBuildInputs;

  meta = {
    homepage = "https://github.com/hyprwm/hyprland-plugins/tree/22de29bc1cf4126202df52691d0bc9a065089cba/hyprexpo";
    description = "Repo-local Hyprexpo package for the removed Hyprland overview plugin";
    license = lib.licenses.bsd3;
    platforms = lib.platforms.linux;
  };
}
