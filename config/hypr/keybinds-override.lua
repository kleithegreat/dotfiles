-- Applies the keybind overrides written by `desktopctl` (if any).
-- The generated data table lives in keybinds-override-data.lua.

local ok, overrides = pcall(require, "./keybinds-override-data")
if not ok or type(overrides) ~= "table" then
    return
end

-- hyprlang wrote "MOD, KEY"; the Lua binder takes "MOD + KEY".
local function combo(mods, key)
    if mods == nil or mods == "" then
        return key
    end
    return (mods:gsub("%s+", " + ")) .. " + " .. key
end

for _, ovr in ipairs(overrides) do
    hl.unbind(combo(ovr.original_mods, ovr.original_key))

    local opts = {}
    if ovr.flags:find("d") and ovr.description ~= "" then
        opts.description = ovr.description
    end
    if ovr.flags:find("e") then
        opts.repeating = true
    end
    if ovr.flags:find("l") then
        opts.locked = true
    end
    if ovr.flags:find("m") then
        opts.mouse = true
    end

    local dispatcher = ovr.arg ~= "" and (ovr.dispatcher .. " " .. ovr.arg) or ovr.dispatcher
    hl.bind(combo(ovr.new_mods, ovr.new_key), hl.dsp.exec_raw(dispatcher), opts)
end
