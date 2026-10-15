local cursor = require("./cursor-theme")

for name, value in pairs(cursor) do
    hl.env(name, value)
end
