-- Applies the animation overrides written by `desktopctl` (if any).
-- The generated data table lives in animations-override-data.lua.

local ok, data = pcall(require, "./animations-override-data")
if not ok or type(data) ~= "table" then
    return
end

for _, bezier in ipairs(data.beziers or {}) do
    hl.curve(bezier.name, {
        type = "bezier",
        points = {
            { bezier.points[1], bezier.points[2] },
            { bezier.points[3], bezier.points[4] },
        },
    })
end

for _, anim in ipairs(data.animations or {}) do
    local spec = {
        leaf = anim.name,
        enabled = anim.enabled,
        speed = anim.speed,
        bezier = anim.curve,
    }
    if anim.style ~= nil and anim.style ~= "" then
        spec.style = anim.style
    end
    hl.animation(spec)
end
