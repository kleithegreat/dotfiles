-- Display topology written by desktopctl, layered on top of the host monitor
-- baseline in monitors.lua. Absent until desktopctl first writes it.
--
-- Only the arrangement is applied here. The primary output the same file
-- records is not: what makes an output primary is the numbered workspaces
-- pinned to it, and those are re-pinned live by the daemon whenever the
-- topology changes -- a reload creates no workspaces for a rule to place.

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
