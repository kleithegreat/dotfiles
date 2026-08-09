-- Host autostart — Desktop

local session = require("./session")
local exec = session.exec

hl.on("hyprland.start", function()
    exec("solaar -w hide")
    exec([[solaar config "MX Master 2S" smart-shift 50]])
end)
