-- Input Configuration
-- Defaults live in input-defaults.lua so desktopctl can read them too;
-- input-runtime.lua is written by desktopctl when settings are changed live.

local defaults = require("./input-defaults")

-- input-runtime.lua is absent until desktopctl first writes it.
local ok, runtime = pcall(require, "./input-runtime")
if not ok or type(runtime) ~= "table" then
    runtime = {}
end

local function pick(key)
    if runtime[key] ~= nil then
        return runtime[key]
    end
    return defaults[key]
end

hl.config({
    input = {
        kb_layout = defaults.kb_layout,

        follow_mouse = defaults.follow_mouse,
        sensitivity = pick("sensitivity"),
        accel_profile = pick("accel_profile"),
        scroll_factor = pick("scroll_factor"),
    },

    cursor = {
        no_hardware_cursors = defaults.no_hardware_cursors,
    },
})
