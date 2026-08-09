-- Environment Variables — shared across hosts

-- Wayland / XDG
hl.env("XDG_CURRENT_DESKTOP", "Hyprland")
hl.env("XDG_SESSION_TYPE", "wayland")
hl.env("XDG_SESSION_DESKTOP", "Hyprland")
hl.env("ELECTRON_OZONE_PLATFORM_HINT", "auto")

-- App compatibility
hl.env("_JAVA_AWT_WM_NONREPARENTING", "1")
hl.env("MOZ_ENABLE_WAYLAND", "1")
