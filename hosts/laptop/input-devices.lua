-- Laptop-specific input settings

hl.config({
    input = {
        touchpad = {
            natural_scroll = true,
            scroll_factor = 0.25,
        },
    },
})

hl.gesture({ fingers = 3, direction = "horizontal", action = "workspace" })
-- hyprexpo's dispatcher is only registered once the plugin loads, so go
-- through a callback rather than naming it at config-parse time.
hl.gesture({
    fingers = 3,
    direction = "up",
    action = function()
        hl.dispatch(hl.dsp.exec_raw("hyprexpo:expo toggle"))
    end,
})

-- When lid handling is inhibited, logind no longer suspends on close; keep the
-- hidden internal panel out of the Hyprland layout while an external output is active.
hl.bind("switch:on:Lid Switch",
    hl.dsp.exec_cmd("desktopctl hypr lid-switch closed --internal eDP-1"), { locked = true })
hl.bind("switch:off:Lid Switch",
    hl.dsp.exec_cmd("desktopctl hypr lid-switch open --internal eDP-1"), { locked = true })

hl.device({
    name = "logitech-mx-master-2s-1",
    sensitivity = -0.2,
})
