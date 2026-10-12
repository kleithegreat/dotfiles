-- Display topology written by desktopctl over monitors.lua; absent until first written.
-- Only the arrangement is applied; the primary output is re-pinned live by the daemon.

local ok, runtime = pcall(require, "./displays-runtime")
if not ok or type(runtime) ~= "table" or type(runtime.outputs) ~= "table" then
    return
end

-- Every field, every time. Through `hyprctl eval` a partial spec merges onto
-- the live monitor, but here it is a *separate rule* from the baseline above,
-- and every field it leaves out falls back to that field's default -- `scale`
-- to `auto`, which quietly rescaled the built-in panel on the next reload.
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
