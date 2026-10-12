-- 在真实界面重放通关搜索的最佳合法方案，每帧最多推进一世代。
-- 沿用 main 的正式生命周期；结果来自外部验证生成的固定记录。
require("main")
local GameStart = Start
local GameStop = Stop
local UI = require("urhox-libs/UI")
local S = require("OriginSimulation")
local Plan = require("OriginWinabilityPlan")
local frame, checked = 0, false

local function check(value, message)
    assert(value, "[通关复核失败] " .. message)
    print("[通关复核通过] " .. message)
end

local function click(ctx, id)
    UI.Layout()
    local widget = assert(ctx.root:FindById(id), id)
    local box = widget:GetAbsoluteLayoutForHitTest()
    local scale = UI.GetScale()
    local data = { pointerId = 0, pointerType = "mouse", button = MOUSEB_LEFT,
        x = (box.x + box.w / 2) * scale, y = (box.y + box.h / 2) * scale }
    UI.HandlePointerDown(UI.PointerEvent.new("PointerDown", data))
    UI.HandlePointerUp(UI.PointerEvent.new("PointerUp", data))
end

function Start()
    GameStart()
    -- 验证使用同一正式推进函数，关闭自动时钟避免验证帧率额外推进。
    UnsubscribeFromEvent("Update")
    local ctx = OriginDebug.GetGame()
    ctx.tipsClosed = true
    check(ctx.seed == Plan.seed, "默认种子一致")
    click(ctx, "action_protect")
    check(ctx.world.round == 0 and ctx.action == "protect", "选择保护不消耗行动")
    click(ctx, "action_protect")
    check(ctx.action == "" and ctx.world.protectionLeft == 3, "取消保护不扣次数")
    click(ctx, "action_craft"); click(ctx, "action_protect")
    check(ctx.action == "protect", "保护与其他行动互斥")
    click(ctx, "confirm")
    check(ctx.world.round == 1 and ctx.world.protectionLeft == 2 and ctx.ticksRemaining == 5, "独立保护消耗一轮和一次机会")
    check(ctx.world.cells[ctx.selectedIndex].protectionTicks == 5, "保护覆盖整轮")
    for _ = 1, 5 do OriginDebug.Advance() end
    check(ctx.world.cells[ctx.selectedIndex].protectionTicks == 0, "五世代后保护恰好结束")
    OriginDebug.Restart()
    check(ctx.milestoneLevel == 0 and ctx.action == "" and ctx.world.protectionLeft == 3, "重开清除里程碑与保护选择")
    SubscribeToEvent("Update", "WinabilityAcceptanceUpdate")
end

function WinabilityAcceptanceUpdate(eventType, eventData)
    frame = frame + 1
    if frame < 10 or checked then return end
    local ctx = OriginDebug.GetGame()
    if ctx.phase == "decision" then
        local record = assert(Plan.actions[ctx.world.round + 1])
        local half = ctx.world.config.regionSize // 2
        OriginDebug.Select(record.x + half, record.y + half)
        check(ctx.regionX == record.x and ctx.regionY == record.y, "干预坐标一致")
        click(ctx, "action_" .. record.action)
        assert(not record.withProtection, "旧附加保护方案不适用于当前规则")
        click(ctx, "confirm")
        check(ctx.phase == "simulation", "真实行动按钮与确认成功")
    elseif ctx.phase == "simulation" then
        OriginDebug.Advance()
    elseif ctx.phase == "ended" then
        local summary = S.Statistics(ctx.world)
        check(ctx.world.generation == Plan.generation and ctx.world.round == Plan.round, "获胜世代与行动数一致")
        check(ctx.world.won and Plan.won and ctx.modalOpen, "真实胜利结算正常显示")
        check(ctx.milestoneLevel == 3 and #ctx.world.history == Plan.generation + 1, "三个里程碑与完整历史均已记录")
        check(math.abs(summary.prosperousShare - Plan.finalShare) < 1e-10, "最终繁荣占比与离线一致")
        check(math.abs(ctx.world.maxProsperousShare - Plan.peak) < 1e-10, "最高繁荣占比与离线一致")
        check(math.abs(summary.population - Plan.population) < 1e-8, "最终人口与离线一致")
        checked = true
        print("[通关复核完成] 合法通关方案已在真实界面复现。")
    end
    assert(frame < 220 or checked, "验证超时：未进入胜利结算")
end

function Stop()
    GameStop()
    check(checked, "验证结束前已完成通关复核")
end
