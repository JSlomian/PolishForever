local _, PF = ...

-- Stub: Interface labels, menus and buttons. Registered so it has a toggle and a place to hook into; it changes nothing yet.
-- Label is "UI" (not the module name "Menus") in Config.lua's checklist: this covers GlobalStrings
-- across the whole interface (menus, buttons, headers, tooltips' static labels, ...), not just
-- literal menus -- "Menus" undersold its actual scope.
PF:RegisterModule("Menus", {
    label = "UI",
    desc = "Interface labels, menus and buttons across the whole UI (not just literal menus)",
    implemented = false,
    OnEnable = function() end,
    OnDisable = function() end,
})
