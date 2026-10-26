-- Float utility windows
for _, class in ipairs({
    "org.pulseaudio.pavucontrol",
    "com.github.wwmm.easyeffects",
    "imv",
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

-- Bitwarden browser extension popup
hl.window_rule({
    match = { class = "chrome-nngceckbapebfimnlniiiahkandclblb-Default" },
    float = true,
    size = "440 720",
    center = true,
})

-- Incognito shares Helium's class; only a fresh window's title tells them apart.
hl.window_rule({
    match = { class = "helium", title = "New Incognito Tab - Helium" },
    float = true,
    size = "monitor_w*0.6 monitor_h*0.7",
    center = true,
})

-- Zoom
hl.window_rule({
    match = { class = "zoom", title = "Zoom Meeting" },
    size = "1200 800",
    center = true,
})

-- Old XWayland Minecraft clients need true fullscreen to cover reserved bar space.
hl.window_rule({
    match = { class = [[^(Minecraft 1\.10\.2)$]] },
    fullscreen_state = "2 2",
})

-- Disable hyprbars on apps with client-side decorations
hl.window_rule({ match = { title = "Discord Updater" }, ["hyprbars:no_bar"] = true })
for _, class in ipairs({ "code", "obsidian", "org.gnome.Nautilus", "zoom" }) do
    hl.window_rule({ match = { class = class }, ["hyprbars:no_bar"] = true })
end

-- Disable hyprbars on tiled windows (bars only on floating)
hl.window_rule({
    name = "no-hyprbars-on-tiled",
    match = { float = false },
    ["hyprbars:no_bar"] = true,
})

-- Layer Rules
-- The threshold has to clear the bar (0.97) and the scrim (0.42) yet skip the
-- transparent window margins, or rounded corners pick up a blur halo.
hl.layer_rule({
    name = "quickshell-blur",
    match = { namespace = "quickshell:.*" },
    blur = true,
    ignore_alpha = 0.35,
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
