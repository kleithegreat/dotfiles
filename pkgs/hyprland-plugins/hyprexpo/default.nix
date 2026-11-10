{
  fetchFromGitHub,
  lib,
  hyprland,
  hyprlandPlugins,
}:

hyprlandPlugins.mkHyprlandPlugin {
  pluginName = "hyprexpo";
  version = "0.57.2-unstable-2026-11-05";

  src = fetchFromGitHub {
    owner = "sandwichfarm";
    repo = "hyprexpo";
    rev = "00a44bf1296ee64c719aec7ae6c8d2fa08fef0dd";
    hash = "sha256-scuBNOlg6AxrjMHdywZJGmsWGoCs330JgqqE2L0sQek=";
  };

  inherit (hyprland) nativeBuildInputs;

  meta = {
    homepage = "https://github.com/sandwichfarm/hyprexpo";
    description = "Maintained Hyprexpo fork with keyboard selection, labels, and gaps";
    license = lib.licenses.bsd3;
    platforms = lib.platforms.linux;
  };
}
