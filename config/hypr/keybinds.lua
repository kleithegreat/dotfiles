-- Keybinds

local mainMod = "SUPER"
local terminal = "alacritty"
local fileManager = "dolphin"

local bind = hl.bind

-- Core
bind(mainMod .. " + Q", hl.dsp.exec_cmd(terminal), { description = "Open terminal" })
bind(mainMod .. " + C", hl.dsp.window.close(), { description = "Close active window" })
bind(mainMod .. " + M", hl.dsp.exit(), { description = "Exit Hyprland" })
bind(mainMod .. " + E", hl.dsp.exec_cmd(fileManager), { description = "Open file manager" })
bind(mainMod .. " + V", hl.dsp.exec_cmd("desktopctl hypr toggle-float"), { description = "Toggle floating window" })
bind(mainMod .. " + R", hl.dsp.exec_cmd("vicinae open"), { description = "Open app launcher" })
bind(mainMod .. " + P", hl.dsp.window.pseudo(), { description = "Toggle pseudotile" })
bind(mainMod .. " + J", hl.dsp.layout("togglesplit"), { description = "Toggle split orientation" })
bind(mainMod .. " + N", hl.dsp.exec_cmd("neovide"), { description = "Open Neovide" })

-- Focus
bind(mainMod .. " + left",  hl.dsp.focus({ direction = "left" }),  { description = "Move focus left" })
bind(mainMod .. " + right", hl.dsp.focus({ direction = "right" }), { description = "Move focus right" })
bind(mainMod .. " + up",    hl.dsp.focus({ direction = "up" }),    { description = "Move focus up" })
bind(mainMod .. " + down",  hl.dsp.focus({ direction = "down" }),  { description = "Move focus down" })

-- Workspaces (9 of them, to match the bar and the hyprexpo overview grid)
for i = 1, 9 do
    bind(mainMod .. " + " .. i, hl.dsp.focus({ workspace = i }),
        { description = "Switch to workspace " .. i })
    bind(mainMod .. " + SHIFT + " .. i, hl.dsp.window.move({ workspace = i }),
        { description = "Move window to workspace " .. i })
end

bind(mainMod .. " + ALT + left",  hl.dsp.focus({ workspace = "e-1" }), { description = "Previous workspace" })
bind(mainMod .. " + ALT + right", hl.dsp.focus({ workspace = "e+1" }), { description = "Next workspace" })

-- Scroll workspaces
bind(mainMod .. " + mouse_down", hl.dsp.focus({ workspace = "e+1" }), { description = "Next workspace" })
bind(mainMod .. " + mouse_up",   hl.dsp.focus({ workspace = "e-1" }), { description = "Previous workspace" })

-- Move/resize with mouse
bind(mainMod .. " + mouse:272", hl.dsp.window.drag(),   { mouse = true })
bind(mainMod .. " + mouse:273", hl.dsp.window.resize(), { mouse = true })

-- Brightness via desktopctl; backend handles backlight/DDC and Quickshell OSD.
bind(mainMod .. " + F6", hl.dsp.exec_cmd("desktopctl brightness down"),
    { description = "Decrease brightness", repeating = true })
bind(mainMod .. " + F7", hl.dsp.exec_cmd("desktopctl brightness up"),
    { description = "Increase brightness", repeating = true })

-- Volume
bind(mainMod .. " + F2", hl.dsp.exec_cmd("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"),
    { description = "Decrease volume", repeating = true })
bind(mainMod .. " + F3", hl.dsp.exec_cmd("wpctl set-volume -l 1.0 @DEFAULT_AUDIO_SINK@ 5%+"),
    { description = "Increase volume", repeating = true })
bind(mainMod .. " + F1", hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"),
    { description = "Toggle mute" })

-- Media
bind(mainMod .. " + F4", hl.dsp.exec_cmd("playerctl play-pause"), { description = "Toggle playback" })

-- Night light (hyprsunset)
bind(mainMod .. " + F8", hl.dsp.exec_cmd("desktopctl night-light toggle"), { description = "Toggle night light" })
bind(mainMod .. " + F9", hl.dsp.exec_cmd("desktopctl night-light auto"), { description = "Return night light to auto" })

-- Screenshot — skip wl-copy when slurp is cancelled so the clipboard survives
bind(mainMod .. " + SHIFT + S",
    hl.dsp.exec_cmd([[sh -c 'geom=$(slurp -d) && grim -g "$geom" - | wl-copy']]),
    { description = "Screenshot selection to clipboard" })
bind(mainMod .. " + F10", hl.dsp.exec_cmd("grim"), { description = "Screenshot full output" })

-- Lock
bind(mainMod .. " + L", hl.dsp.exec_cmd("loginctl lock-session"), { description = "Lock session" })

bind(mainMod .. " + Escape",
    hl.dsp.exec_cmd([[sh -lc 'qs -p "${XDG_CONFIG_HOME:-$HOME/.config}/quickshell" ipc call popups togglePowerMenu']]),
    { description = "Toggle power menu" })
bind(mainMod .. " + SHIFT + N",
    hl.dsp.exec_cmd([[sh -lc 'qs -p "${XDG_CONFIG_HOME:-$HOME/.config}/quickshell" ipc call popups toggleDrawer']]),
    { description = "Toggle notifications drawer" })

-- Settings panel
bind(mainMod .. " + T",
    hl.dsp.exec_cmd([[sh -lc 'qs -p "${XDG_CONFIG_HOME:-$HOME/.config}/quickshell" ipc call settings toggle']]),
    { description = "Toggle settings" })

-- Restart Quickshell
bind(mainMod .. " + SHIFT + Q",
    hl.dsp.exec_cmd("pkill quickshell || true; sleep 0.3; desktopctl launch-quickshell"),
    { description = "Restart Quickshell" })

-- Window switcher (snappy-switcher)
bind("ALT + Tab", hl.dsp.exec_cmd("snappy-switcher next --workspace --mod alt"),
    { description = "Next item in switcher" })
bind("ALT + SHIFT + Tab", hl.dsp.exec_cmd("snappy-switcher prev --workspace --mod alt"),
    { description = "Previous item in switcher" })

-- A closure bound here registers but never fires; route through `hyprctl eval`,
-- where `expo()` does work.
bind(mainMod .. " + grave",
    hl.dsp.exec_cmd([[hyprctl eval 'hl.plugin.hyprexpo.expo("toggle")']]),
    { description = "Toggle workspace overview" })
