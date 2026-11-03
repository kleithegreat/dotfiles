local colors = require("./colors")

local pluginDir = os.getenv("HYPR_PLUGIN_DIR")

hl.plugin.load(pluginDir .. "/lib/libhyprbars.so")
hl.plugin.load(pluginDir .. "/lib/libhyprspace.so")

local function dispatch(expression)
    return "hyprctl dispatch '" .. expression .. "'"
end

-- client = -1 leaves the client's own fullscreen state alone.
local maximize = dispatch(
    'hl.dsp.window.fullscreen_state({ internal = 1; client = -1; action = "toggle" })')

hl.config({
    plugin = {
        hyprbars = {
            bar_height = 24,
            bar_color = colors.bg1_rgba,
            ["col.text"] = colors.fg_rgba,
            bar_text_font = colors.sys_font,
            bar_text_size = 10,
            bar_buttons_alignment = "left",
            bar_button_padding = 8,
            on_double_click = maximize,
        },

        overview = {
            panelColor = colors.bg_rgba,
            workspaceActiveBorder = colors.fg_rgba,
            workspaceInactiveBorder = colors.bg1_rgba,
            -- The laptop's own 3-finger gestures drive it; its built-in swipe would double-fire.
            disableGestures = true,
        },
    },
})

local function button(color, icon, action)
    hl.plugin.hyprbars.add_button({
        bg_color = color,
        fg_color = colors.fg_rgba,
        size = 14,
        icon = icon,
        action = action,
    })
end

button(colors.red_rgba, "", dispatch("hl.dsp.window.close()"))
button(colors.yellow_rgba, "", maximize)
button(colors.green_rgba, "",
    dispatch('hl.dsp.window.move({ workspace = "special"; silent = true })'))
