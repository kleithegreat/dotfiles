-- Host autostart — Laptop

local session = require("./session")
local exec = session.exec

hl.on("hyprland.start", function()
    exec("solaar -w hide")
    exec("desktopctl hypr lid-switch sync --internal eDP-1")
    -- The MX Master 2S caps smart-shift at 50; Solaar documents that as always ratcheted.
    exec([[solaar config "MX Master 2S" scroll-ratchet Ratcheted]])
    exec([[solaar config "MX Master 2S" smart-shift 50]])
end)
