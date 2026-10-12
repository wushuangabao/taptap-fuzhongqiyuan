-- 本地真实窗口验收入口；正式入口仍为 main.lua。
require("main")
local GameStart, GameUpdate = Start, HandleUpdate
local UI = require("urhox-libs/UI")
local View = require("OriginView")
local frame = 0
local stopped = false
local function Click(id)
    UI.Layout()
    local widget = assert(OriginDebug.GetGame().root:FindById(id), id)
    local l = widget:GetAbsoluteLayoutForHitTest()
    for _, kind in ipairs({"Down", "Up"}) do
        UI.HandlePointerEvent(UI.PointerEvent.new("Pointer" .. kind, {pointerId = 0,
            pointerType = "mouse", button = MOUSEB_LEFT,
            x = (l.x + l.w / 2) * UI.GetScale(), y = (l.y + l.h / 2) * UI.GetScale()}))
    end
end
local function Capture(name)
    local image = Image()
    assert(graphics:TakeScreenShot(image))
    assert(image:SavePNG("map-layers-" .. name .. ".png"))
    print("[地图图层截图] " .. name)
end
local function CheckRow()
    UI.Layout()
    local ctx = OriginDebug.GetGame()
    local previousRight = 0
    for _, id in ipairs({"layer_quality", "layer_population", "layer_institution", "layer_terrain", "regionToggle", "migrationToggle"}) do
        local l = ctx.root:FindById(id):GetAbsoluteLayoutForHitTest()
        assert(l.x >= previousRight - 0.5, id .. " overlaps")
        assert(l.w >= (id:find("Toggle") and 76 or 48), id .. " too narrow: " .. l.w)
        previousRight = l.x + l.w
    end
end
local steps = {
    [20] = function() CheckRow(); Capture("quality") end,
    [30] = function() Click("layer_terrain"); assert(OriginDebug.GetGame().layer == "terrain") end,
    [40] = function() Capture("terrain") end,
    [50] = function() Click("regionToggle"); assert(not OriginDebug.GetGame().showRegions) end,
    [60] = function() Capture("terrain-hidden") end,
    [70] = function() Click("layer_quality"); assert(not OriginDebug.GetGame().showRegions) end,
    [80] = function() Capture("quality-hidden") end,
    [90] = function() Click("layer_population"); assert(OriginDebug.GetGame().layer == "population") end,
    [100] = function() Capture("population-hidden") end,
    [110] = function() Click("layer_institution"); assert(OriginDebug.GetGame().layer == "institution"); Click("regionToggle"); assert(OriginDebug.GetGame().showRegions) end,
    [120] = function() Capture("institution") end,
    [130] = function()
        UI.SetScale(1.8)
        UI.GetViewportSize = function() return 780, 420 end
        local ctx = OriginDebug.GetGame()
        View.Build(ctx)
        ctx.root:SetStyle({width = 780, height = 420})
        View.Resize(ctx); UI.Layout()
        CheckRow()
        Click("regionToggle"); assert(not ctx.showRegions)
        Click("layer_terrain"); assert(ctx.layer == "terrain" and not ctx.showRegions)
    end,
    [140] = function() Capture("compact"); print("[地图图层验收] PASS"); stopped = true end,
}
function Start()
    GameStart()
    UnsubscribeFromEvent("Update")
    SubscribeToEvent("Update", "OriginMapLayersAcceptanceUpdate")
end
function OriginMapLayersAcceptanceUpdate(eventType, eventData)
    GameUpdate(eventType, eventData)
    if stopped then return end
    frame = frame + 1
    if steps[frame] then
        local ok, err = pcall(steps[frame])
        if not ok then stopped = true; print("[地图图层验收] FAIL " .. tostring(err)) end
    end
end
