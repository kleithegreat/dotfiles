local okTheme, theme = pcall(require, "./appearance-theme")
if not okTheme or type(theme) ~= "table" then
    theme = {}
end

local okColors, colors = pcall(require, "./colors")

local function boolOr(value, fallback)
    if value == nil then
        return fallback
    end
    return value
end

local general = {
    gaps_in = theme.gaps_in or 4,
    gaps_out = theme.gaps_out or 6,
    border_size = theme.border_size or 2,
}

if okColors and type(colors) == "table" then
    if colors.accent_rgba then
        general["col.active_border"] = colors.accent_rgba
    end
    if colors.bg2_rgba then
        general["col.inactive_border"] = colors.bg2_rgba
    end
end

hl.config({
    general = general,

    decoration = {
        rounding = theme.rounding or 8,

        blur = {
            enabled = boolOr(theme.blur_enabled, true),
            size = theme.blur_size or 8,
            passes = theme.blur_passes or 2,
        },
    },

    animations = {
        enabled = boolOr(theme.animations_enabled, true),
    },

    dwindle = {
        preserve_split = true,
    },

    misc = {
        disable_hyprland_logo = true,
        disable_splash_rendering = true,
        force_default_wallpaper = 0,
    },
})

hl.curve("myBezier", { type = "bezier", points = { { 0.05, 0.9 }, { 0.1, 1.05 } } })

hl.animation({ leaf = "windows",    enabled = true, speed = 4,  bezier = "myBezier" })
hl.animation({ leaf = "windowsOut", enabled = true, speed = 4,  bezier = "myBezier", style = "popin 80%" })
hl.animation({ leaf = "border",     enabled = true, speed = 10, bezier = "myBezier" })
hl.animation({ leaf = "fade",       enabled = true, speed = 4,  bezier = "myBezier" })
hl.animation({ leaf = "workspaces", enabled = true, speed = 4,  bezier = "myBezier" })
