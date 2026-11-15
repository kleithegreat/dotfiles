hl.config({
    input = {
        touchpad = {
            natural_scroll = true,
        },
    },
})

hl.gesture({ fingers = 3, direction = "horizontal", action = "workspace" })
-- Resolved at gesture time: plugins.lua loads after this file.
hl.gesture({
    fingers = 3,
    direction = "up",
    action = function()
        hl.plugin.hyprexpo.expo("on")
    end,
})
hl.gesture({
    fingers = 3,
    direction = "down",
    action = function()
        hl.plugin.hyprexpo.expo("off")
    end,
})

-- With lid handling inhibited, keep the hidden panel out of the layout while an external is active.
hl.bind("switch:on:Lid Switch",
    hl.dsp.exec_cmd("desktopctl hypr lid-switch closed --internal eDP-1"), { locked = true })
hl.bind("switch:off:Lid Switch",
    hl.dsp.exec_cmd("desktopctl hypr lid-switch open --internal eDP-1"), { locked = true })
