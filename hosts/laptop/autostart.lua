-- Host autostart — Laptop

local session = require("./session")
local exec = session.exec

hl.on("hyprland.start", function()
    exec("desktopctl hypr lid-switch sync --internal eDP-1")
end)
