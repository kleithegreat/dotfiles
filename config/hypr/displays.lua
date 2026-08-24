-- Display topology written by desktopctl, layered on top of the host monitor
-- baseline in monitors.lua. Absent until desktopctl first writes it.
--
-- Only the arrangement is applied here. The primary output the same file
-- records is not: what makes an output primary is the numbered workspaces
-- pinned to it, and those are re-pinned live by the daemon whenever the
-- topology changes -- a reload creates no workspaces for a rule to place.

local ok, runtime = pcall(require, "./displays-runtime")
if not ok or type(runtime) ~= "table" or type(runtime.positions) ~= "table" then
    return
end

-- Every arranged output is declared, never just the one that moved: an output
-- left on `position = "auto"` re-resolves against the new geometry and slides
-- somewhere nobody asked for.
for selector, position in pairs(runtime.positions) do
    hl.monitor({ output = selector, position = position })
end
