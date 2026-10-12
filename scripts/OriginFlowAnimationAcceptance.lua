-- 真实窗口验收入口；正式main不加载。使用正式模拟生成传播，通过真实UI事件切换。
require("main")
local GameStart, GameUpdate = Start, HandleUpdate
local UI = require("urhox-libs/UI")
local View = require("OriginView")
local S = require("OriginSimulation")
local V = require("OriginTechnologyVisuals")
local frame, stopped = 0, false
local stableGeneration, stableDraws, stableRng = 0, 0, 0

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
    assert(image:SavePNG("flow-animation-" .. name .. ".png"))
    local world = OriginDebug.GetGame().world
    assert(world.generation == stableGeneration and world.rng.draws == stableDraws and world.rng.state == stableRng)
    print("[流光截图] " .. name)
end

local function SetClock(value)
    local ctx = OriginDebug.GetGame()
    local map = assert(ctx.root:FindById("worldMap")) --[[@as OriginMap]]
    ctx.phase = "simulation"
    ctx.pendingGeneration = {lastReport = ctx.world.lastReport}
    ctx.accumulator = value
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
        ctx.speed = 1
        for _ = 1, 10 do S.Tick(ctx.world) end
        stableGeneration, stableDraws, stableRng = ctx.world.generation, ctx.world.rng.draws, ctx.world.rng.state
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
        SetClock(1)
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
    [80] = function() SetClock(1) end,
    [85] = function() Capture("local-phase-a") end,
    [90] = function() SetClock(1.2) end,
    [95] = function() Capture("local-phase-b") end,
    [100] = function() SetClock(1.4) end,
    [105] = function() Capture("local-phase-c") end,
    [110] = function() Click("technologyToggle"); Check(false) end,
    [120] = function() Capture("global-detail") end,
    [125] = function()
        local ctx = OriginDebug.GetGame()
        local best = ctx.world.lastReport.flows[1]
        for _, flow in ipairs(ctx.world.lastReport.flows) do if flow.amount > best.amount then best = flow end end
        local cell = ctx.world.cells[best.from]
        ctx.selectCell(cell.x, cell.y)
        local map = assert(ctx.root:FindById("worldMap")) --[[@as OriginMap]]
        map.camera.centerX, map.camera.centerY = (cell.x - 0.5) / ctx.world.width, (cell.y - 0.5) / ctx.world.height
        Click("technologyToggle")
        SetClock(require("OriginEvolution").GenerationSeconds * 0.375)
        print("[流光检查] 真实迁移边 " .. #ctx.world.lastReport.flows .. " 最大流量 " .. best.amount)
    end,
    [135] = function() Capture("migration-on") end,
    [140] = function() Click("migrationToggle"); assert(not OriginDebug.GetGame().showMigration) end,
    [150] = function() Capture("migration-off") end,
    [155] = function() Click("migrationToggle"); assert(OriginDebug.GetGame().showMigration); Click("technologyToggle") end,
    [160] = function()
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
    [175] = function() Capture("global-compact"); print("[流光验收] PASS world/RNG unchanged"); stopped = true end,
}

function Start()
    GameStart()
    UnsubscribeFromEvent("Update")
    SubscribeToEvent("Update", "OriginFlowAnimationAcceptanceUpdate")
end

function OriginFlowAnimationAcceptanceUpdate(eventType, eventData)
    GameUpdate(eventType, eventData)
    if stopped then return end
    frame = frame + 1
    if steps[frame] then
        local ok, err = pcall(steps[frame])
        if not ok then stopped = true; print("[流光验收] FAIL " .. tostring(err)) end
    end
end
