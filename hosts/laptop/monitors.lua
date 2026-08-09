-- Monitor Configuration — Laptop

local external = "desc:BNQ ZOWIE XL LCD EB12M01465SL0"

hl.monitor({ output = external, mode = "1920x1080@120.00", position = "0x0", scale = 1 })
hl.monitor({ output = "eDP-1", mode = "1920x1200@59.95", position = "auto", scale = 1 })
hl.monitor({ output = "", mode = "preferred", position = "auto", scale = 1 })

-- Hyprland requires every enabled monitor to have an active workspace. Keep the
-- normal numbered workspaces on the external monitor when it is attached, so the
-- laptop panel behaves as a secondary surface instead of taking 1-10.
for i = 1, 10 do
    local rule = { workspace = tostring(i), monitor = external }
    if i == 1 then
        rule.default = true
    end
    hl.workspace_rule(rule)
end
