-- 本地真实窗口检查入口：检查分界线开关和四个勾选项的布局，正式入口仍为main。
require("main")
local GameStart, GameUpdate = Start, HandleUpdate
local UI = require("urhox-libs/UI")
local View = require("OriginView")
local OriginalViewport, OriginalScale = UI.GetViewportSize, UI.GetScale()
local frame, stopped = 0, false

local function Click(id)
    UI.Layout()
    local widget = assert(OriginDebug.GetGame().root:FindById(id))
    local l = widget:GetAbsoluteLayoutForHitTest()
    for _, kind in ipairs({"Down", "Up"}) do
        UI.HandlePointerEvent(UI.PointerEvent.new("Pointer" .. kind, {pointerId = 0,
            pointerType = "mouse", button = MOUSEB_LEFT,
            x = (l.x + l.w / 2) * UI.GetScale(), y = (l.y + l.h / 2) * UI.GetScale()}))
    end
end

local function CheckRow(expectSplit)
    UI.Layout()
    local ctx = OriginDebug.GetGame()
    local controls = assert(ctx.root:FindById("mapTools")):GetAbsoluteLayoutForHitTest()
    local right, rowY = controls.x, nil
    for _, id in ipairs({"regionToggle", "gridToggle", "migrationToggle", "technologyToggle", "zoomLabel", "mapZoom", "resetMap"}) do
        if id == "zoomLabel" then right, rowY = controls.x, nil end
        local widget = assert(ctx.root:FindById(id))
        local l = widget:GetAbsoluteLayoutForHitTest()
        assert(l.x >= right - 0.5, id .. " overlaps")
        assert(l.x + l.w <= controls.x + controls.w + 0.5, id .. " outside controls")
        if id:find("Toggle") then
            assert(l.w >= (id == "technologyToggle" and 54 or 64) - 0.5, id .. " clips label")
            local label = assert(ctx.root:FindById(id .. "Label")):GetAbsoluteLayoutForHitTest()
            assert(label.x + label.w <= l.x + l.w + 0.5, id .. " text outside checkbox")
            assert(ctx.root:FindById(id .. "Label").props.fontSize == 10, id .. " font changed")
            if rowY then assert(math.abs(l.y - rowY) < 0.5) end
            rowY = l.y
        end
        right = l.x + l.w
    end
    local split = ctx.root:FindById("mapOptions").props.flexDirection == "column"
    if expectSplit ~= nil then assert(split == expectSplit, "响应布局不符合预期") end
    local toggles = ctx.root:FindById("mapToggleRow"):GetAbsoluteLayoutForHitTest()
    local zoom = ctx.root:FindById("mapZoomRow"):GetAbsoluteLayoutForHitTest()
    if split then assert(zoom.y >= toggles.y + toggles.h + 3.5, "缩放区域必须另起一行")
    else assert(zoom.x >= toggles.x + toggles.w + 5.5 and math.abs(zoom.y - toggles.y) < 0.5) end
    assert(not ctx.root:FindById("milestone_1") and not ctx.root:FindById("milestoneWin"), "旧阶段文案未删除")
    local journey = ctx.root:FindById("journey"):GetAbsoluteLayoutForHitTest()
    for _, id in ipairs({"shortfallSummary", "nextGoal"}) do
        local label = ctx.root:FindById(id):GetAbsoluteLayoutForHitTest()
        assert(label.y >= journey.y and label.y + label.h <= journey.y + journey.h + 0.5, "提示被裁剪")
    end
    local checkbox = assert(ctx.root:FindById("gridToggle")) --[[@as Checkbox]]
    assert(checkbox:IsChecked() == ctx.showGrid)
    print("[地块分界检查] 控件与文字不重叠；字号10；阶段行已删除；分行=" .. tostring(split) .. "；显示=" .. tostring(ctx.showGrid))
end

local function Capture(name)
    local image = Image()
    assert(graphics:TakeScreenShot(image))
    assert(image:SavePNG("grid-lines-" .. name .. ".png"))
    print("[地块分界截图] " .. name)
end

local steps = {
    [20] = function() assert(not OriginDebug.GetGame().showGrid); CheckRow(false) end,
    [35] = function() Capture("off") end,
    [45] = function()
        local ctx = OriginDebug.GetGame()
        local regions, migration, technology = ctx.showRegions, ctx.showMigration, ctx.showTechnology
        Click("gridToggle"); assert(ctx.showGrid)
        assert(ctx.showRegions == regions and ctx.showMigration == migration and ctx.showTechnology == technology)
        View.Refresh(ctx); CheckRow()
    end,
    [60] = function() Capture("on") end,
    [70] = function() Click("regionToggle"); Click("layer_terrain"); assert(OriginDebug.GetGame().showGrid); CheckRow() end,
    [85] = function() Capture("terrain") end,
    [95] = function() Click("gridToggle"); assert(not OriginDebug.GetGame().showGrid); CheckRow() end,
    [110] = function() Capture("terrain-off") end,
    [120] = function()
        UI.SetScale(1.8)
        UI.GetViewportSize = function() return 780, 420 end
        local ctx = OriginDebug.GetGame()
        View.Build(ctx); ctx.root:SetStyle({width = 780, height = 420})
        View.Resize(ctx); UI.Layout(); CheckRow(true)
        Click("gridToggle"); assert(ctx.showGrid); CheckRow(true)
    end,
    [135] = function() Capture("compact") end,
    [145] = function()
        UI.SetScale(OriginalScale); UI.GetViewportSize = OriginalViewport
        local ctx = OriginDebug.GetGame()
        View.Build(ctx); UI.Layout(); CheckRow(false)
    end,
    [160] = function() Capture("wide-restored"); print("[地块分界验收] PASS"); stopped = true end,
}

function Start()
    GameStart()
    UnsubscribeFromEvent("Update")
    SubscribeToEvent("Update", "OriginGridLinesAcceptanceUpdate")
end

function OriginGridLinesAcceptanceUpdate(eventType, eventData)
    GameUpdate(eventType, eventData)
    if stopped then return end
    frame = frame + 1
    if steps[frame] then
        local ok, err = pcall(steps[frame])
        if not ok then stopped = true; print("[地块分界验收] FAIL " .. tostring(err)) end
    end
end
