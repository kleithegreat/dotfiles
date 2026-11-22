local ok, cursor = pcall(require, "./cursor-theme")
if not ok or type(cursor) ~= "table" then
    return
end

for name, value in pairs(cursor) do
    hl.env(name, value)
end
