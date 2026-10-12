-- 开发验收入口，正式游戏仍以 main.lua 为入口。
require("main")
local GameStart = Start
local UI = require("urhox-libs/UI")
local Tests = require("OriginTests")
local Simulation = require("OriginSimulation")
local acceptanceFrame = 0
local endingFrame = 0

local function Check(condition, message)
    assert(condition, "[验收失败] " .. message)
    print("[验收通过] " .. message)
end

local function ClickAt(x, y)
    local scale = UI.GetScale()
    local data = {pointerId = 0, pointerType = "mouse", button = MOUSEB_LEFT, x = x * scale, y = y * scale}
    UI.HandlePointerDown(UI.PointerEvent.new("PointerDown", data))
    UI.HandlePointerUp(UI.PointerEvent.new("PointerUp", data))
end

local function ClickWidget(ctx, id)
    local widget = assert(ctx.root:FindById(id), "控件不存在：" .. id)
    local l = widget:GetAbsoluteLayoutForHitTest()
    ClickAt(l.x + l.w / 2, l.y + l.h / 2)
end

function Start()
    GameStart()
    UnsubscribeFromEvent("Update")
    OriginDebug.ClosePanel()
    local testReport = Tests.Run()
    Check(testReport.ok, string.format("核心测试%d/%d通过", testReport.passed, testReport.total))
    local ctx = OriginDebug.GetGame()
    Check(#ctx.world.cells == 384, "世界包含384个地块")
    Check(ctx.world.generation == 0 and ctx.world.round == 0, "开局未赠送或消耗行动")
    OriginDebug.Select(24, 16)
    Check(ctx.selectedIndex == 384 and ctx.regionX == 24 and ctx.regionY == 16, "边缘只选择点击的一个地块")
    OriginDebug.Select(12, 8)
    local before = ctx.world.cells[ctx.selectedIndex].craft
    OriginDebug.Choose("craft")
    ctx.tipsClosed = true
    OriginDebug.Confirm()
    Check(ctx.phase == "simulation" and ctx.ticksRemaining == 5, "确认后进入五世代演进")
    local succeeded = ctx.world.actions[1].improvements[1].succeeded
    Check(math.abs(ctx.world.cells[ctx.selectedIndex].craft - before * (succeeded and 1.15 or 1)) < 1e-10,
        "确认按抽签结果执行工艺改良，失败也占用本轮")
    OriginDebug.Confirm()
    Check(ctx.world.round == 1, "演进期二次确认不赠送行动")
    ctx.paused = true
    OriginDebug.Advance()
    Check(ctx.world.generation == 0, "暂停不推进模拟")
    ctx.paused = false
    for _ = 1, 5 do OriginDebug.Advance() end
    Check(ctx.phase == "decision" and ctx.world.generation == 5, "五世代后返回决策期")
    Check(#ctx.world.history == 6, "历史包含初始与每世代数据")
    local replay = Simulation.Replay(ctx.seed, ctx.world.actions)
    Check(math.abs(replay.cells[1].population - ctx.world.cells[1].population) < 1e-10, "真实行动记录可确定性重放")
    OriginDebug.Choose("craft")
    OriginDebug.Choose("protect")
    OriginDebug.Confirm()
    Check(ctx.world.protectionLeft == 2, "制度保护单独消耗一轮和一次机会")
    Check(ctx.world.cells[ctx.selectedIndex].protectionTicks == 5, "保护即时覆盖五次竞争")
    for _ = 1, 5 do OriginDebug.Advance() end
    Check(ctx.world.cells[ctx.selectedIndex].protectionTicks == 0, "保护五次后恰好结束")
    OriginDebug.Restart()
    Check(ctx.world.generation == 0 and ctx.world.protectionLeft == 3, "同种子重开清空进度与保护次数")
    SubscribeToEvent("Update", "AcceptanceUpdate")
    print("[验收] 逻辑与交互接口检查完成，继续检查渲染与说明浮层。")
end

---@param eventType string
---@param eventData UpdateEventData
function AcceptanceUpdate(eventType, eventData)
    acceptanceFrame = acceptanceFrame + 1
    local ctx = OriginDebug.GetGame()
    if acceptanceFrame == 10 then
        UI.Layout()
        local map = ctx.root:FindById("worldMap") --[[@as OriginMap?]]
        Check(map ~= nil, "地图控件存在")
        if map then
            local b = map:Geometry()
            ClickAt(b.x + (7 - 0.5) * b.cw, b.y + (6 - 0.5) * b.ch)
            Check(ctx.selectedIndex == (6 - 1) * 24 + 7, "真实指针点击可选中地图格子")
        end
        UI.Layout()
        ClickWidget(ctx, "layer_institution")
        Check(ctx.layer == "institution", "真实指针可切换制度图层")
        UI.Layout()
        ClickWidget(ctx, "action_craft")
        Check(ctx.action == "craft", "真实指针可选择工艺行动")
        ClickWidget(ctx, "confirm")
        Check(ctx.phase == "simulation", "真实确认按钮可推进世代")
        ClickWidget(ctx, "pauseToggle")
        Check(ctx.paused, "真实暂停按钮停止演进")
        local generation = ctx.world.generation
        OriginDebug.Advance()
        Check(ctx.world.generation == generation, "暂停观察不多赠世代")
        ClickWidget(ctx, "pauseToggle")
        for _ = 1, 5 do OriginDebug.Advance() end
        Check(ctx.phase == "decision", "真实按钮行动后返回决策")
        OriginDebug.Restart()
    elseif acceptanceFrame == 20 then
        ctx.layer = "institution"
        OriginDebug.Select(5, 5)
    elseif acceptanceFrame == 30 then
        OriginDebug.Help()
        Check(ctx.modalOpen, "说明浮层打开")
    elseif acceptanceFrame == 45 then
        -- 点击弹窗外关闭，且不穿透选择地图。
        ClickAt(8, UI.GetHeight() / 2)
    elseif acceptanceFrame == 55 then
        Check(not ctx.modalOpen, "说明浮层关闭并释放")
    elseif acceptanceFrame > 55 and endingFrame == 0 then
        if ctx.phase == "decision" then
            local round = ctx.world.round + 1
            OriginDebug.Select(2 + ((round - 1) % 7) * 3, 2 + (math.floor((round - 1) / 7) % 4) * 3)
            OriginDebug.Choose("craft")
            OriginDebug.Confirm()
            return
        elseif ctx.phase == "simulation" then
            OriginDebug.Advance()
            return
        end
        Check(ctx.phase == "ended", "完整游戏进入结算")
        Check(ctx.world.generation == 250 and not ctx.world.won, "未通关路线在250世代进入结算")
        Check(ctx.world.round == 50 and #ctx.world.history == ctx.world.generation + 1, "结算行动与历史数量正确")
        Check(ctx.modalOpen, "真实事件结局浮层打开")
        local finalRound = ctx.world.round
        OriginDebug.Confirm()
        Check(ctx.world.round == finalRound, "结算后不能追加行动")
        endingFrame = acceptanceFrame
        print("[验收] 完整50轮、制度图层与真实事件结算已执行。")
    elseif endingFrame > 0 and acceptanceFrame == endingFrame + 20 then
        OriginDebug.ClosePanel()
        Check(not ctx.modalOpen, "结算关闭后可继续检查地图")
    end
end
