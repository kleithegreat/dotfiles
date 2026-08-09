-- Hyprland plugins
-- HYPR_PLUGIN_DIR is provided by the NixOS system configuration.

local colors = require("./colors")

local pluginDir = os.getenv("HYPR_PLUGIN_DIR")

hl.plugin.load(pluginDir .. "/lib/libhyprbars.so")
hl.plugin.load(pluginDir .. "/lib/libhyprexpo.so")

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
            on_double_click = "hyprctl dispatch fullscreen 1",

            ["hyprbars-button"] = {
                colors.red_rgba .. ", 14, , hyprctl dispatch killactive",
                colors.yellow_rgba .. ", 14, , hyprctl dispatch fullscreen 1",
                colors.green_rgba .. ", 14, , hyprctl dispatch movetoworkspacesilent special",
            },
        },

        hyprexpo = {
            columns = 3,
            gaps_in = 5,
            bg_col = colors.bg_rgba,
            workspace_method = "first 1",
        },
    },
})
