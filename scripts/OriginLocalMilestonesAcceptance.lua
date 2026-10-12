-- 独立引擎验收入口；不由正式游戏加载。测试夹具用于验证UI，不证明正式地图通关。
-- Runtime 运行此入口后检查日志与横屏/小屏截图；缺少截图时视觉结果为 UNDETERMINED。
require("main")
local GameStart = Start
local UI = require("urhox-libs/UI")
local View = require("OriginView")
local S = require("OriginSimulation")
local Progress = require("OriginProgress")
local checks = 0
local frame = 0
local function Check(value, message)
    assert(value, "[局部成果界面失败] " .. message)
    checks = checks + 1
    print("[局部成果界面通过] " .. message)
end
local function CheckBounds(id, parentId)
    local root = OriginDebug.GetGame().root
    local l = assert(root:FindById(id)):GetAbsoluteLayout()
    local p = assert(root:FindById(parentId)):GetAbsoluteLayout()
    Check(l.w > 0 and l.h > 0 and l.x >= p.x - 1 and l.x + l.w <= p.x + p.w + 1
        and l.y >= p.y - 1 and l.y + l.h <= p.y + p.h + 1, id .. "位于容器内")
end
local function Click(id)
    UI.Layout()
    local l = assert(OriginDebug.GetGame().root:FindById(id)):GetAbsoluteLayoutForHitTest()
    for _, kind in ipairs({"PointerDown", "PointerUp"}) do
        UI.HandlePointerEvent(UI.PointerEvent.new(kind, {pointerId = 0, pointerType = "mouse", button = MOUSEB_LEFT,
            x = (l.x + l.w / 2) * UI.GetScale(), y = (l.y + l.h / 2) * UI.GetScale()}))
    end
end
local function Exercise()
    local ctx = OriginDebug.GetGame()
    ctx.world = S.New(ctx.seed, {naturalGrowthRate = 0, migrationRate = 0, replacementRate = 0, mobilizeAgricultureGrowth = 0, exploreAgricultureGrowth = 0})
    for _, cell in ipairs(ctx.world.cells) do
        cell.population, cell.landCapacity, cell.agriculture, cell.foodShare, cell.craft = 40, 40, 3.9, 0.5, 2
        cell.institution = "mobilize"
    end
    S.RefreshMetrics(ctx.world)
    ctx.localProgress, ctx.phase, ctx.tipsClosed = Progress.Local.New(), "decision", true
    OriginDebug.Select(12, 8)
    View.Build(ctx); UI.Layout()
    Click("action_agriculture"); Click("confirm")
    Check(ctx.phase == "simulation" and ctx.localProgress.pending, "指针确认实际行动后才登记目标")
    local regionX = ctx.localProgress.pending.region.x
    OriginDebug.Select(20, 12)
    Check(ctx.localProgress.pending.region.x == regionX, "移动选区保留原干预范围")
    OriginDebug.Advance()
    Check(ctx.localProgress.completed.technology and not ctx.localProgress.completed.food, "传播来自真实报告，温饱等待轮末")
    for _ = 2, ctx.world.config.generationsPerRound do OriginDebug.Advance() end
    Check(ctx.localProgress.completed.food and not ctx.modalOpen, "轮末记录温饱成果，不自动开弹窗")
    OriginDebug.Select(12, 8)
    Click("action_institution"); Click("confirm")
    for _ = 1, ctx.world.config.generationsPerRound do OriginDebug.Advance() end
    Check(ctx.localProgress.completed.exploration and #ctx.localProgress.history == 3, "探索存续整轮后保留三类成果")
    local count = #ctx.localProgress.history
    View.OnGeneration(ctx); View.Refresh(ctx)
    Check(#ctx.localProgress.history == count, "刷新和重复结算不重复记录")
    local label = ctx.root:FindById("nextGoal") --[[@as Label]]
    Check(label:GetText():find("局部成果") and not label:GetText():find("格"), "常驻反馈使用日常语言")
    UI.Layout(); CheckBounds("nextGoal", "journey")
    Click("openTrends"); UI.Layout()
    Check(ctx.root:FindById("localEvent_food") and ctx.root:FindById("localEvent_technology")
        and ctx.root:FindById("localEvent_exploration"), "文明进程展示完成历史")
    CheckBounds("sheetCard", "safe")
    print("[局部成果截图检查点] 标准横屏历史")
end
local function Compact()
    local ctx = OriginDebug.GetGame()
    OriginDebug.ClosePanel()
    UI.SetScale(1.8)
    UI.GetViewportSize = function() return 780, 420 end
    GetSafeAreaInsets = function() return Rect(57.6, 0, 57.6, 32.4) end
    sdk = {GetNativeExitMenuRect = function() return {bottom = 72 / graphics.height} end}
    ctx.root:SetStyle({width = 780, height = 420})
    View.Resize(ctx); UI.Layout()
    CheckBounds("nextGoal", "journey")
    Click("openTrends"); UI.Layout(); CheckBounds("sheetCard", "safe")
    Check(ctx.root:FindById("localMilestoneHistory") and ctx.root:FindById("sheetScroll").props.scrollY,
        "小屏完成历史在已有滚动面板内")
    print("[局部成果截图检查点] 小屏历史")
end
function Start()
    GameStart()
    SubscribeToEvent("Update", "LocalMilestonesAcceptanceUpdate")
end
function LocalMilestonesAcceptanceUpdate()
    frame = frame + 1
    if frame == 5 then Exercise()
    elseif frame == 10 then Compact()
    elseif frame == 15 then
        local ctx = OriginDebug.GetGame()
        OriginDebug.ClosePanel(); OriginDebug.Restart()
        Check(#ctx.localProgress.history == 0 and not ctx.localProgress.pending, "正式重开入口清空成果和追踪")
        print(string.format("[局部成果界面验收] 完成%d项检查。", checks))
    end
end
