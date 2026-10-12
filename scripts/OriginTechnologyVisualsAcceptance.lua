-- 真实窗口验收入口；正式main不加载。使用正式模拟生成传播，通过真实UI事件切换。
require("main")
local GameStart, GameUpdate = Start, HandleUpdate
local UI = require("urhox-libs/UI")
local View = require("OriginView")
local S = require("OriginSimulation")
local V = require("OriginTechnologyVisuals")
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

local function Capture(name)
    local image = Image()
    assert(graphics:TakeScreenShot(image))
    assert(image:SavePNG("technology-flow-" .. name .. ".png"))
    print("[技术流截图] " .. name)
end

local function Check(localOnly)
    UI.Layout()
    local ctx = OriginDebug.GetGame()
    local map = assert(ctx.root:FindById("worldMap")) --[[@as OriginMap]]
    assert(ctx.showTechnology == not localOnly)
    local actual = V.Arrows(ctx.world, map:Geometry(), map:GetAbsoluteLayout(), ctx.showTechnology, ctx.selectedIndex)
    local expected, incoming, outgoing = 0, 0, 0
    for _, flow in ipairs(ctx.world.lastReport.technologyFlows) do
        if flow.to == ctx.selectedIndex then incoming = incoming + 1 end
        if flow.from == ctx.selectedIndex then outgoing = outgoing + 1 end
        if not localOnly or flow.from == ctx.selectedIndex or flow.to == ctx.selectedIndex then expected = expected + 1 end
    end
    -- 全图视角没有视口外的传播；细节视角只核对所选地块周围的可见流。
    if map.camera.zoom <= 1.01 or localOnly then assert(#actual == expected, #actual .. "/" .. expected) end
    assert(incoming > 0 and outgoing > 0, "所选地块应有真实传入和传出")
    print(string.format("[技术流检查] %s 可见%d 传入%d 传出%d 格宽%.2f", localOnly and "局部" or "全图",
        #actual, incoming, outgoing, map:Geometry().cw))
end

local steps = {
    [20] = function()
        local ctx = OriginDebug.GetGame()
        ctx.paused = true
        for _ = 1, 10 do S.Tick(ctx.world) end
        local best, bestCount = 1, 0
        for i in ipairs(ctx.world.cells) do
            local incoming, outgoing = 0, 0
            for _, flow in ipairs(ctx.world.lastReport.technologyFlows) do
                if flow.from == i then outgoing = outgoing + 1 end
                if flow.to == i then incoming = incoming + 1 end
            end
            if incoming > 0 and outgoing > 0 and incoming + outgoing > bestCount then
                best, bestCount = i, incoming + outgoing
            end
        end
        local cell = ctx.world.cells[best]
        ctx.selectCell(cell.x, cell.y)
        View.Refresh(ctx)
        local map = assert(ctx.root:FindById("worldMap")) --[[@as OriginMap]]
        map:ResetCamera()
        Check(false)
    end,
    [35] = function() Capture("global") end,
    [45] = function() Click("technologyToggle"); Check(true) end,
    [60] = function() Capture("local") end,
    [70] = function()
        local ctx = OriginDebug.GetGame()
        local map = assert(ctx.root:FindById("worldMap")) --[[@as OriginMap]]
        local cell = ctx.world.cells[ctx.selectedIndex]
        map:SetZoom(3)
        map.camera.centerX, map.camera.centerY = (cell.x - 0.5) / ctx.world.width, (cell.y - 0.5) / ctx.world.height
        Check(true)
    end,
    [85] = function() Capture("local-detail") end,
    [95] = function() Click("technologyToggle"); Check(false) end,
    [110] = function() Capture("global-detail") end,
    [120] = function()
        UI.SetScale(1.8)
        UI.GetViewportSize = function() return 780, 420 end
        local ctx = OriginDebug.GetGame()
        View.Build(ctx)
        ctx.root:SetStyle({width = 780, height = 420})
        View.Resize(ctx); UI.Layout()
        local map = assert(ctx.root:FindById("worldMap")) --[[@as OriginMap]]
        map:ResetCamera()
        assert(map:Geometry().cw < 22, "小视口应进入原来隐藏箭头的细节等级")
        Check(false)
    end,
    [135] = function() Capture("global-compact"); print("[技术流验收] PASS"); stopped = true end,
}

function Start()
    GameStart()
    UnsubscribeFromEvent("Update")
    SubscribeToEvent("Update", "OriginTechnologyVisualsAcceptanceUpdate")
end

function OriginTechnologyVisualsAcceptanceUpdate(eventType, eventData)
    GameUpdate(eventType, eventData)
    if stopped then return end
    frame = frame + 1
    if steps[frame] then
        local ok, err = pcall(steps[frame])
        if not ok then stopped = true; print("[技术流验收] FAIL " .. tostring(err)) end
    end
end
