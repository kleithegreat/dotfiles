-- Cursor environment
-- Values come from `desktopctl theme`; this file just applies them.

local cursor = require("./cursor-theme")

for name, value in pairs(cursor) do
    hl.env(name, value)
end
