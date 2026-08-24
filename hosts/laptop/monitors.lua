-- Monitor Configuration — Laptop
--
-- Modes only. Where each output sits and which one is primary are runtime
-- state owned by desktopctl (`displays.lua`), because neither can be written
-- ahead of time for a monitor this host has never met.

hl.monitor({ output = "desc:BNQ ZOWIE XL LCD EB12M01465SL0", mode = "1920x1080@120.00", position = "auto", scale = 1 })
hl.monitor({ output = "eDP-1", mode = "1920x1200@59.95", position = "auto", scale = 1 })
hl.monitor({ output = "", mode = "preferred", position = "auto", scale = 1 })
