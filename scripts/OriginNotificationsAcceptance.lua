-- 独立真实运行时验收入口；截图留在 savedata，复制时放 .tmp/screenshots/toast/。
require("main")
local GameStart, GameUpdate = Start, HandleUpdate
local UI = require("urhox-libs/UI")
local View = require("OriginView")
local frame, done = 0, false
---@type {panel: Panel, progress: ProgressBar, duration: number, remaining: number, hovered: boolean}
local notice
local text = "居民向生活更好的相邻地块迁移，会将原本的习惯带到当地。"
local function Ctx() return OriginDebug.GetGame() end
local function Capture(name)
    local image = Image()
    assert(graphics:TakeScreenShot(image))
    local l = Ctx().notifications.stack:GetAbsoluteLayout()
    local s = UI.GetScale()
    image = image:GetSubimage(IntRect(math.floor(l.x * s), math.floor(l.y * s),
        math.ceil((l.x + l.w) * s), math.ceil((l.y + l.h) * s)))
    assert(image:SavePNG("notifications-" .. name .. ".png"))
end
local function MoveTo(widget)
    local l = widget:GetAbsoluteLayoutForHitTest()
    UI.HandlePointerMove(UI.PointerEvent.new("PointerMove", {
        pointerId = 0, pointerType = "mouse",
        x = (l.x + l.w / 2) * UI.GetScale(), y = (l.y + l.h / 2) * UI.GetScale(),
    }))
end
local function MoveAway()
    UI.HandlePointerMove(UI.PointerEvent.new("PointerMove", {pointerId = 0, pointerType = "mouse", x = -20, y = -20}))
end
local function Click(widget)
    UI.Layout()
    local box = widget:GetAbsoluteLayoutForHitTest()
    for _, kind in ipairs({"Down", "Up"}) do
        UI.HandlePointerEvent(UI.PointerEvent.new("Pointer" .. kind, {
            pointerId = 0, pointerType = "mouse", button = MOUSEB_LEFT,
            x = (box.x + box.w / 2) * UI.GetScale(), y = (box.y + box.h / 2) * UI.GetScale(),
        }))
    end
end
local function CheckAllPanelClocks(ctx)
    local map = ctx.root:FindById("worldMap") --[[@as OriginMap]]
    local timer = ctx.notifications:Show("面板暂停验收")
    local function Step()
        GameUpdate("Update", {GetFloat = function() return 0.25 end} --[[@as UpdateEventData]])
        map:Update(0.25)
    end
    local function Frozen(name)
        assert(ctx.modalOpen, name .. "必须进入统一暂停状态")
        local generation, age, elapsed = ctx.world.generation, ctx.tickAge, ctx.accumulator
        local clock, remaining, pending = map.clock, timer.remaining, ctx.pendingGeneration
        for _ = 1, 40 do Step() end
        OriginDebug.Advance()
        assert(ctx.world.generation == generation and ctx.pendingGeneration == pending, name .. "不能推进或替换世代")
        assert(ctx.tickAge == age and ctx.accumulator == elapsed and map.clock == clock, name .. "必须冻结全部地图动画")
        assert(timer.remaining == remaining, name .. "必须冻结通知倒计时")
    end
    MoveAway(); Step()
    for _, kind in ipairs({"help", "trends", "restart", "settings"}) do
        View.OpenPanel(ctx, kind); Frozen(kind)
        if kind == "settings" then
            for _, id in ipairs({"settingsMigration", "settingsCompetition"}) do
                ctx.root:FindById(id).props.onClick(); Frozen(id)
                View.ClosePanel(ctx); Frozen("返回参数主页")
            end
        elseif kind == "restart" then
            ctx.root:FindById("restartSettings").props.onClick(); Frozen("下一局参数草稿")
            View.ClosePanel(ctx); Frozen("返回重新开始")
        end
        View.ClosePanel(ctx, true)
        local before = ctx.accumulator
        Step(); assert(ctx.accumulator > before, "关闭面板后继续原动画进度")
    end
    View.Ending(ctx); Frozen("结算面板"); View.ClosePanel(ctx, true)
    ctx.paused = true
    View.Help(ctx); Frozen("手动暂停时打开帮助"); View.ClosePanel(ctx)
    local age, elapsed, remaining = ctx.tickAge, ctx.accumulator, timer.remaining
    Step()
    assert(ctx.paused and ctx.tickAge == age and ctx.accumulator == elapsed and timer.remaining == remaining,
        "关闭面板不得解除原有手动暂停")
    ctx.paused = false
    ctx.notifications:Dismiss(timer)
end
local function CheckLayout(narrow)
    UI.Layout()
    local previousBottom = 0
    for _, item in ipairs(Ctx().notifications.items) do
        local card = item.panel:GetAbsoluteLayout()
        local label = item.panel:GetChildren()[1] --[[@as Label]]
        local body = label:GetAbsoluteLayout()
        local close = item.panel:FindById("notificationClose"):GetAbsoluteLayout()
        if narrow then assert(body.h > 28, "窄宽度下长正文应显示为多行") end
        assert(body.y + body.h <= card.y + card.h - 10, "正文底部必须在卡片内")
        assert(body.x + body.w <= close.x - 6, "正文不能被关闭按钮遮挡")
        if item.timed then
            local bar = item.progress:GetAbsoluteLayout()
            assert(bar.w > 0 and bar.y >= body.y + body.h and bar.y + bar.h <= card.y + card.h,
                "底部进度条必须有宽度且不覆盖正文")
            assert(item.progress.props.showLabel == false, "进度条不能显示数字")
        end
        assert(card.y >= previousBottom, "新通知必须插在空白区域，不能遮挡其他通知")
        previousBottom = card.y + card.h + 8
    end
    local originalLabel = notice.panel:GetChildren()[1] --[[@as Label]]
    assert(originalLabel:GetText() == text, "必须保留完整正文")
end
local steps = {
    [10] = function()
        MoveAway()
        notice = Ctx().notifications:Show(text)
        assert(notice.duration == 8 and notice.remaining == 8, "所有常规提示统一8秒")
        Ctx().notifications:Show("竞争力强的地块，其制度会向周边传播。", {duration = 0})
        Ctx().notifications:Show("繁荣出现了！满足温饱的同时，生活用品也达到人均富足。", {duration = 0})
        assert(#Ctx().notifications.items == 3, "多个提示可以同时显示")
    end,
    [30] = function()
        CheckLayout()
        assert(Ctx().notifications.stack:GetAbsoluteLayout().w == 520, "常规提示加宽至520")
        local manager = Ctx().notifications --[[@as table]]
        local beforePause = notice.remaining
        Ctx().paused = true; View.UpdateTips(Ctx(), 20); Ctx().paused = false
        assert(notice.remaining == beforePause, "游戏暂停时通知不计时")
        View.Help(Ctx())
        assert(Ctx().modalOpen, "真实帮助面板已打开")
        View.UpdateTips(Ctx(), 20)
        assert(notice.remaining == beforePause, "面板打开时通知不计时")
        View.ClosePanel(Ctx())
        MoveAway(); manager:Update(1, false)
        local beforeHover = notice.remaining
        local progressBefore = notice.progress:GetValue()
        assert(progressBefore < 1 and math.abs(progressBefore - beforeHover / 8) < 0.0001,
            "进度条比例必须与剩余时间一致")
        MoveTo(notice.panel:GetChildren()[1])
        assert(notice.hovered, "鼠标移入正文应暂停计时")
        manager:Update(20, false)
        assert(notice.remaining == beforeHover and notice.progress:GetValue() == progressBefore,
            "悬停超过总时长仍保留通知和进度")
        MoveTo(notice.panel:FindById("notificationClose"))
        manager:Update(20, false)
        assert(notice.hovered and notice.remaining == beforeHover, "移动至关闭按钮仍保持暂停")
        MoveAway(); manager:Update(1, false)
        assert(not notice.hovered and notice.remaining == beforeHover - 1, "移开后从剩余时间继续")
        assert(notice.progress:GetValue() < progressBefore, "移开后进度条继续减少")
        Capture("wide")
    end,
    [50] = function()
        local manager = Ctx().notifications --[[@as table]]
        manager:Dismiss(manager.items[2])
        manager:Show("里程碑：已有10%人口达到繁荣", {duration = 0})
        CheckLayout()
        assert(#manager.items == 3, "中间提示移除后新提示可补位且不遮挡")
        local box = notice.panel:FindById("notificationClose"):GetAbsoluteLayoutForHitTest()
        for _, kind in ipairs({"Down", "Up"}) do
            UI.HandlePointerEvent(UI.PointerEvent.new("Pointer" .. kind, {
                pointerId = 0, pointerType = "mouse", button = MOUSEB_LEFT,
                x = (box.x + box.w / 2) * UI.GetScale(), y = (box.y + box.h / 2) * UI.GetScale(),
            }))
        end
        assert(#Ctx().notifications.items == 2, "真实点击关闭只能移除目标通知")
        while #manager.items > 0 do manager:Dismiss(manager.items[1]) end
        Ctx().notifications:Show("自动消失测试", {duration = 0.1})
    end,
    [90] = function()
        MoveAway(); Ctx().notifications:Update(1, false)
        assert(#Ctx().notifications.items == 0, "计时结束后必须移除通知")
        Ctx().notifications.layer:SetStyle({width = "100%"})
        OriginDebug.Restart(20261002)
        assert(#Ctx().notifications.items == 0, "重开必须清理通知")
        local ctx = Ctx()
        ctx.tipsClosed = true
        local cell = ctx.world.cells[ctx.selectedIndex]
        local a, b, f, institution = cell.agriculture, cell.craft, cell.foodShare, cell.institution
        local draws = ctx.world.rng.draws
        Click(ctx.root:FindById("action_craft")); Click(ctx.root:FindById("action_protect"))
        assert(ctx.action == "protect", "真实点击保护替换原先行动")
        Click(ctx.root:FindById("confirm"))
        assert(ctx.world.actions[1].action == "protect" and not ctx.world.actions[1].withProtection)
        assert(ctx.world.round == 1 and ctx.world.protectionLeft == 2 and cell.protectionTicks == 5)
        assert(cell.agriculture == a and cell.craft == b and cell.foodShare == f and cell.institution == institution)
        assert(ctx.world.rng.draws == draws, "独立保护不触发改良抽签")
        CheckAllPanelClocks(ctx)
        for _ = 1, 5 do OriginDebug.Advance() end
        assert(ctx.phase == "decision" and ctx.world.cells[ctx.selectedIndex].protectionTicks == 0,
            "保护完整持续五世代后到期")
        OriginDebug.Restart(20261002)
        Ctx().tipsClosed = false
        done = true
        print("[通知验收完成] 多条不遮挡与补位、8秒与悬停、进度条、关闭、自动消失、重开、独立保护、所有面板冻结通知/世代/动画并恢复全部通过")
    end,
}
function Start()
    GameStart()
    UnsubscribeFromEvent("Update")
    SubscribeToEvent("Update", "OriginNotificationsAcceptanceUpdate")
end
function OriginNotificationsAcceptanceUpdate(eventType, eventData)
    GameUpdate(eventType, eventData)
    if done then return end
    frame = frame + 1
    if steps[frame] then
        local ok, err = pcall(steps[frame])
        if not ok then done = true; print("[通知验收失败] " .. tostring(err)) end
    end
end
