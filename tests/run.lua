-- Runs every test file in its own Lua process. From the repo root:
--   lua5.1 tests/run.lua
local tests = {
    "tests/core_test.lua",
    "tests/scan_test.lua",
    "tests/scan_classic_ui_test.lua",
    "tests/prices_test.lua",
    "tests/tooltip_test.lua",
    "tests/migration_test.lua",
    "tests/broker_test.lua",
    "tests/post_test.lua",
    "tests/flip_test.lua",
    "tests/sell_test.lua",
    "tests/history_test.lua",
    "tests/outside_test.lua",
    "tests/selltab_test.lua",
    "tests/pick_test.lua",
}
local lua = arg and arg[-1] or "lua5.1"
local failed = 0
for _, path in ipairs(tests) do
    local ok = os.execute(lua .. " " .. path)
    if ok ~= 0 and ok ~= true then failed = failed + 1 end
end
if failed > 0 then
    print(failed .. " test file(s) failed")
    os.exit(1)
end
