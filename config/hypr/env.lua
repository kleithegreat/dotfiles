-- Environment Variables

-- Wayland / XDG
hl.env("XDG_CURRENT_DESKTOP", "Hyprland")
hl.env("XDG_SESSION_TYPE", "wayland")
hl.env("XDG_SESSION_DESKTOP", "Hyprland")
hl.env("ELECTRON_OZONE_PLATFORM_HINT", "auto")

-- GPU — Intel Iris Xe as primary, NVIDIA as secondary
hl.env("LIBVA_DRIVER_NAME", "iHD")
hl.env("AQ_DRM_DEVICES", "/dev/dri/card2:/dev/dri/card1")
-- __EGL_VENDOR_LIBRARY_FILENAMES is set in the host NixOS modules, not here.

-- App compatibility
hl.env("_JAVA_AWT_WM_NONREPARENTING", "1")
hl.env("MOZ_ENABLE_WAYLAND", "1")
