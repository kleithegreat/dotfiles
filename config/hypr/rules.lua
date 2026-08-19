-- Window Rules

-- Float utility windows
for _, class in ipairs({
    "org.pulseaudio.pavucontrol",
    "com.github.wwmm.easyeffects",
    "imv",
    "f3d",
    "org.kde.ark",
    "org.kde.filelight",
    "io.missioncenter.MissionCenter",
    "org.kde.kompare",
    "org.kde.partitionmanager",
    "zoom",
}) do
    hl.window_rule({ match = { class = class }, float = true })
end

-- Float and center dialogs
-- hyprpolkitagent sets no app_id (empty class); match its Qt application name.
hl.window_rule({ match = { title = "Hyprland Polkit Agent" }, float = true, center = true })
for _, class in ipairs({
    "org.gnome.World.Secrets",
    "org.kde.kcharselect",
    "org.kde.isoimagewriter",
    "Bitwarden",
}) do
    hl.window_rule({ match = { class = class }, float = true, center = true })
end

-- KDE portal file picker
hl.window_rule({
    match = { class = "org.freedesktop.impl.portal.desktop.kde" },
    float = true,
    size = "900 600",
    center = true,
})

-- Bitwarden browser extension popup
hl.window_rule({
    match = { class = "chrome-nngceckbapebfimnlniiiahkandclblb-Default" },
    float = true,
    size = "440 720",
    center = true,
})

-- Zoom
hl.window_rule({
    match = { class = "zoom", title = "Zoom Meeting" },
    size = "1200 800",
    center = true,
})

hl.window_rule({
    match = { class = "google-chrome", title = [[\(Incognito\)]] },
    float = true,
})

-- Old XWayland Minecraft clients need true fullscreen to cover reserved bar space.
hl.window_rule({
    match = { class = [[^(Minecraft 1\.10\.2)$]] },
    fullscreen_state = "2 2",
})

-- Layer Rules
-- Quickshell blur. The shell's glass sits at 0.62 (bar) and 0.76 (panels), so
-- the threshold has to clear both while still skipping the transparent window
-- margins, the full-screen overlay's gaps and its scrim -- otherwise rounded
-- corners pick up a blur halo and the scrim blurs the desktop behind it.
hl.layer_rule({
    name = "quickshell-blur",
    match = { namespace = "quickshell:.*" },
    blur = true,
    ignore_alpha = 0.35,
})

-- Disable hyprbars on apps with client-side decorations
hl.window_rule({ match = { title = "Discord Updater" }, ["hyprbars:no_bar"] = true })
for _, class in ipairs({ "code", "obsidian", "org.gnome.Nautilus" }) do
    hl.window_rule({ match = { class = class }, ["hyprbars:no_bar"] = true })
end

-- Disable hyprbars on tiled windows (bars only on floating)
hl.window_rule({
    name = "no-hyprbars-on-tiled",
    match = { float = false },
    ["hyprbars:no_bar"] = true,
})

hl.layer_rule({
    name = "vicinae-blur",
    match = { namespace = "vicinae" },
    blur = true,
    ignore_alpha = 0,
})

hl.layer_rule({
    name = "vicinae-no-animation",
    match = { namespace = "vicinae" },
    no_anim = true,
})
