-- Arrangement written by desktopctl; the daemon pins the primary output live.

local ok, runtime = pcall(require, "./displays-runtime")
if not ok or type(runtime) ~= "table" or type(runtime.outputs) ~= "table" then
    return
end

-- Every field, every time: here an omitted field resets; see docs/hyprland.md.
for selector, spec in pairs(runtime.outputs) do
    if spec.disabled then
        hl.monitor({ output = selector, disabled = true })
    else
        hl.monitor({
            output = selector,
            mode = spec.mode,
            position = spec.position,
            scale = spec.scale,
            vrr = spec.vrr,
            transform = spec.transform,
            disabled = false,
        })
    end
end
