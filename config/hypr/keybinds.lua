-- Keybinds

local mainMod = "SUPER"
local terminal = "alacritty"
local fileManager = "dolphin"

-- Core
hl.bind(mainMod .. " + Q", hl.dsp.exec_cmd(terminal), { description = "Open terminal" })
hl.bind(mainMod .. " + C", hl.dsp.window.close(), { description = "Close active window" })
hl.bind(mainMod .. " + M", hl.dsp.exit(), { description = "Exit Hyprland" })
hl.bind(mainMod .. " + E", hl.dsp.exec_cmd(fileManager), { description = "Open file manager" })
hl.bind(mainMod .. " + V", hl.dsp.exec_cmd("desktopctl hypr toggle-float"), { description = "Toggle floating window" })
hl.bind(mainMod .. " + R", hl.dsp.exec_cmd("vicinae open"), { description = "Open app launcher" })
hl.bind(mainMod .. " + P", hl.dsp.window.pseudo(), { description = "Toggle pseudotile" })
hl.bind(mainMod .. " + J", hl.dsp.layout("togglesplit"), { description = "Toggle split orientation" })
hl.bind(mainMod .. " + N", hl.dsp.exec_cmd("neovide"), { description = "Open Neovide" })

-- Focus
hl.bind(mainMod .. " + left",  hl.dsp.focus({ direction = "left" }),  { description = "Move focus left" })
hl.bind(mainMod .. " + right", hl.dsp.focus({ direction = "right" }), { description = "Move focus right" })
hl.bind(mainMod .. " + up",    hl.dsp.focus({ direction = "up" }),    { description = "Move focus up" })
hl.bind(mainMod .. " + down",  hl.dsp.focus({ direction = "down" }),  { description = "Move focus down" })

-- Workspaces (key 0 maps to workspace 10)
for i = 1, 10 do
    local key = i % 10
    hl.bind(mainMod .. " + " .. key, hl.dsp.focus({ workspace = i }),
        { description = "Switch to workspace " .. i })
    hl.bind(mainMod .. " + SHIFT + " .. key, hl.dsp.window.move({ workspace = i }),
        { description = "Move window to workspace " .. i })
end

hl.bind(mainMod .. " + ALT + left",  hl.dsp.focus({ workspace = "e-1" }), { description = "Previous workspace" })
hl.bind(mainMod .. " + ALT + right", hl.dsp.focus({ workspace = "e+1" }), { description = "Next workspace" })

-- Scroll workspaces
hl.bind(mainMod .. " + mouse_down", hl.dsp.focus({ workspace = "e+1" }), { description = "Next workspace" })
hl.bind(mainMod .. " + mouse_up",   hl.dsp.focus({ workspace = "e-1" }), { description = "Previous workspace" })

-- Move/resize with mouse
hl.bind(mainMod .. " + mouse:272", hl.dsp.window.drag(),   { mouse = true })
hl.bind(mainMod .. " + mouse:273", hl.dsp.window.resize(), { mouse = true })

-- Brightness via desktopctl; backend handles backlight/DDC and Quickshell OSD.
hl.bind(mainMod .. " + F6", hl.dsp.exec_cmd("desktopctl brightness down"),
    { description = "Decrease brightness", repeating = true })
hl.bind(mainMod .. " + F7", hl.dsp.exec_cmd("desktopctl brightness up"),
    { description = "Increase brightness", repeating = true })

-- Volume
hl.bind(mainMod .. " + F2", hl.dsp.exec_cmd("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"),
    { description = "Decrease volume", repeating = true })
hl.bind(mainMod .. " + F3", hl.dsp.exec_cmd("wpctl set-volume -l 1.0 @DEFAULT_AUDIO_SINK@ 5%+"),
    { description = "Increase volume", repeating = true })
hl.bind(mainMod .. " + F1", hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"),
    { description = "Toggle mute" })

-- Media
hl.bind(mainMod .. " + F4", hl.dsp.exec_cmd("playerctl play-pause"), { description = "Toggle playback" })

-- Night light (hyprsunset)
hl.bind(mainMod .. " + F8", hl.dsp.exec_cmd("desktopctl night-light toggle"), { description = "Toggle night light" })
hl.bind(mainMod .. " + F9", hl.dsp.exec_cmd("desktopctl night-light auto"), { description = "Return night light to auto" })

-- Screenshot — skip wl-copy when slurp is cancelled so the clipboard survives
hl.bind(mainMod .. " + SHIFT + S",
    hl.dsp.exec_cmd([[sh -c 'geom=$(slurp -d) && grim -g "$geom" - | wl-copy']]),
    { description = "Screenshot selection to clipboard" })
hl.bind(mainMod .. " + F10", hl.dsp.exec_cmd("grim"), { description = "Screenshot full output" })

-- Lock
hl.bind(mainMod .. " + L", hl.dsp.exec_cmd("loginctl lock-session"), { description = "Lock session" })

hl.bind(mainMod .. " + Escape",
    hl.dsp.exec_cmd([[sh -lc 'qs -p "${DESKTOPCTL_REPO:-$HOME/repos/dotfiles}/config/quickshell" ipc call popups togglePowerMenu']]),
    { description = "Toggle power menu" })
hl.bind(mainMod .. " + SHIFT + N",
    hl.dsp.exec_cmd([[sh -lc 'qs -p "${DESKTOPCTL_REPO:-$HOME/repos/dotfiles}/config/quickshell" ipc call popups toggleDrawer']]),
    { description = "Toggle notifications drawer" })

-- Settings panel
hl.bind(mainMod .. " + T",
    hl.dsp.exec_cmd([[sh -lc 'qs -p "${DESKTOPCTL_REPO:-$HOME/repos/dotfiles}/config/quickshell" ipc call settings toggle']]),
    { description = "Toggle settings" })

-- Restart Quickshell
hl.bind(mainMod .. " + SHIFT + Q",
    hl.dsp.exec_cmd("pkill quickshell || true; sleep 0.3; desktopctl launch-quickshell"),
    { description = "Restart Quickshell" })

-- Window switcher (snappy-switcher)
hl.bind("ALT + Tab", hl.dsp.exec_cmd("snappy-switcher next --workspace --mod alt"),
    { description = "Next item in switcher" })
hl.bind("ALT + SHIFT + Tab", hl.dsp.exec_cmd("snappy-switcher prev --workspace --mod alt"),
    { description = "Previous item in switcher" })

-- Workspace overview (hyprexpo plugin). The hl.plugin.* namespace only exists
-- once the plugin has loaded, so dispatch the raw dispatcher string instead.
hl.bind(mainMod .. " + grave", hl.dsp.exec_raw("hyprexpo:expo toggle"),
    { description = "Toggle workspace overview" })
