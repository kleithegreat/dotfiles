-- Input defaults.
-- desktopctl reads this file for the baseline it layers runtime overrides on,
-- so keep it a flat data table with one scalar field per line.

return {
    kb_layout = "us",
    follow_mouse = 1,
    sensitivity = 0.75,
    accel_profile = "flat",
    scroll_factor = 1.0,
    no_hardware_cursors = true,
}
