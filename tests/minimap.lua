return function(addon, check)
    addon.UI:AddMinimapButton()
    local button = addon.UI.minimapButton
    local settings = addon.DB:GetSettings()
    local previous = settings.minimap
    local oldPoint, oldParent = rawget(button, "SetPoint"), rawget(button, "GetParent")
    local oldWidth, oldHeight = Minimap.width, Minimap.height
    local oldCenter, oldScale = rawget(Minimap, "GetCenter"), rawget(Minimap, "GetEffectiveScale")
    local oldUIScale = rawget(UIParent, "GetEffectiveScale")
    local oldShift = IsShiftKeyDown
    local shift = false
    IsShiftKeyDown = function() return shift end
    local oldCursorX, oldCursorY = cursorX, cursorY
    local anchor
    button.SetPoint = function(_, ...) anchor = { ... } end
    button.GetParent = function(self) return self.parent end
    settings.minimap = { angle = 0, free = true, x = 999, y = 888, hidden = false }
    Minimap:SetSize(300, 300)
    addon.UI:PositionMinimapButton()
    check(anchor[2] == UIParent and anchor[4] == 999 and anchor[5] == 888 and settings.minimap.free,
        "Saved free position was lost")
    settings.minimap.free = false
    addon.UI:PositionMinimapButton()
    check(anchor[2] == Minimap and button.parent == Minimap and not settings.minimap.free,
        "Docked icon not parented to minimap")
    check(math.abs(anchor[4] - 154) < 0.001 and math.abs(anchor[5]) < 0.001,
        "Icon inside enlarged minimap instead of on its edge")
    Minimap:SetSize(400, 200)
    settings.minimap.angle = 90
    for _, hook in ipairs(Minimap.hooks.OnSizeChanged) do hook(Minimap, 400, 200) end
    check(math.abs(anchor[4]) < 0.001 and math.abs(anchor[5] - 104) < 0.001,
        "Icon did not follow minimap resize")
    Minimap.GetCenter = function() return 100, 200 end
    Minimap.GetEffectiveScale = function() return 2 end
    UIParent.GetEffectiveScale = function() return 0.5 end
    button.scripts.OnDragStart(button)
    cursorX, cursorY = 200 + 2000, 400
    button.scripts.OnUpdate(button, 0.016)
    check(not settings.minimap.free and anchor[2] == Minimap and math.abs(anchor[4] - 204) < 0.001,
        "Far drag detached icon or mixed cursor/minimap scales")
    cursorX, cursorY = 200 + 204 * 2, 400 + 104 * 2
    button.scripts.OnUpdate(button, 0.016)
    check(math.abs(settings.minimap.angle - 45) < 0.001,
        "Scaled elliptical minimap drag missed cursor direction")
    local angle = settings.minimap.angle
    cursorX, cursorY = 200, 400
    button.scripts.OnUpdate(button, 0.016)
    check(settings.minimap.angle == angle, "Dragging through center reset the angle")
    button.scripts.OnDragStop(button)
    check(button.scripts.OnUpdate == nil, "Minimap drag kept updating after release")
    shift = true
    button.scripts.OnDragStart(button)
    shift = false -- Mode remains stable if Shift is released before the mouse.
    cursorX, cursorY = 800, 450
    button.scripts.OnUpdate(button, 0.016)
    button.scripts.OnDragStop(button)
    check(settings.minimap.free and button.parent == UIParent and anchor[4] == 1600 and anchor[5] == 900,
        "Shift-drag did not preserve free placement in UI coordinates")
    for _, hook in ipairs(Minimap.hooks.OnSizeChanged) do hook(Minimap, 400, 200) end
    check(anchor[2] == UIParent and anchor[4] == 1600 and anchor[5] == 900,
        "Minimap refresh moved free icon")
    button.scripts.OnDragStart(button)
    button.scripts.OnUpdate(button, 0.016)
    button.scripts.OnDragStop(button)
    check(not settings.minimap.free and button.parent == Minimap,
        "Normal drag did not reattach free icon")
    settings.minimap.free = true
    addon.UI:ResetMinimapButton()
    check(not settings.minimap.free and settings.minimap.angle == 225 and anchor[2] == Minimap,
        "Reset did not restore docked default position")
    settings.minimap.hidden = true
    addon.UI:RefreshMinimapButton()
    check(not button:IsShown(), "Docking ignored hidden icon preference")
    settings.minimap = previous
    button.SetPoint, button.GetParent = oldPoint, oldParent
    Minimap.width, Minimap.height = oldWidth, oldHeight
    Minimap.GetCenter, Minimap.GetEffectiveScale = oldCenter, oldScale
    UIParent.GetEffectiveScale = oldUIScale
    IsShiftKeyDown = oldShift
    cursorX, cursorY = oldCursorX, oldCursorY
    addon.UI:RefreshMinimapButton()
end
