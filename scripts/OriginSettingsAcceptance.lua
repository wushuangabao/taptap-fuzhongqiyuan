-- 可复用的真实窗口验收入口；仅在明确启动/运行中的本地预览中使用。
-- 截图留在引擎 savedata 沙箱；复制回项目时仅放 .tmp/screenshots/settings/。
require("main")
local GameStart, GameUpdate = Start, HandleUpdate
local UI = require("urhox-libs/UI")
local S = require("OriginSimulation")
local frame, checks, stopped = 0, 0, false
---@type OriginWorld
local world
local rng, originalScale, originalViewport
local function Ctx() return OriginDebug.GetGame() end
local function Find(id) return assert(Ctx().root:FindById(id), "缺少控件：" .. id) end
local function Check(value, message)
    assert(value, message)
    checks = checks + 1
    print("[设置验收通过] " .. message)
end
local function Click(id)
    UI.Layout()
    local l = Find(id):GetAbsoluteLayoutForHitTest()
    for _, kind in ipairs({"Down", "Up"}) do
        UI.HandlePointerEvent(UI.PointerEvent.new("Pointer" .. kind, {
            pointerId = 0, pointerType = "mouse", button = MOUSEB_LEFT,
            x = (l.x + l.w / 2) * UI.GetScale(), y = (l.y + l.h / 2) * UI.GetScale(),
        }))
    end
end
local function ScrollTo(id)
    UI.Layout()
    local scroll = Find("sheetScroll") --[[@as ScrollView]]
    scroll:UpdateContentSize()
    local target = Find(id):GetAbsoluteLayout()
    scroll:SetScroll(0, target.y - scroll:GetAbsoluteLayout().y - 12)
end
local function Bottom()
    UI.Layout()
    local scroll = Find("sheetScroll") --[[@as ScrollView]]
    scroll:UpdateContentSize(); scroll:ScrollToBottom()
end
local function Type(key, text)
    local id = "setting_" .. key
    ScrollTo(id); Click(id)
    local input = Find(id) --[[@as TextField]]
    input:SelectAll(); UI.HandleTextInput(text)
    Check(input:GetValue() == text, "真实输入：" .. key)
end
local function Screenshot(name)
    local captured = Image()
    assert(graphics:TakeScreenShot(captured))
    assert(captured:SavePNG("settings-" .. name .. ".png"))
    print("[设置验收截图] settings-" .. name .. ".png")
end
local steps = {
    [10] = function()
        world, rng = Ctx().world, Ctx().world.rng.state
        Click("openSettings")
        Check(Ctx().panel == "settings_main", "右上角打开设置")
        Check(Find("setting_mobilizeAgricultureGrowth").props.disabled and not Ctx().root:FindById("settingsSave"), "对局只读")
    end,
    [20] = function() Screenshot("readonly"); ScrollTo("populationCurve") end,
    [30] = function()
        Screenshot("curve-default")
        Click("settingsClose"); Click("openRestart"); Bottom(); Click("restartSettings")
        Check(not Find("setting_naturalGrowthRate").props.disabled, "重开入口允许编辑")
        Type("naturalGrowthSlope", "4"); Type("naturalGrowthRate", "20")
        ScrollTo("populationCurve")
    end,
    [40] = function()
        Screenshot("curve-edited")
        Check(Find("populationCurve").config.naturalGrowthSlope == 4 and Find("populationCurve").config.naturalGrowthRate == .2, "曲线读取草稿")
        Check(Ctx().world == world and world.rng.state == rng and world.config.naturalGrowthRate == .5, "编辑不改变本局")
        local label = Find("settingLabel_naturalGrowthSlope")
        ScrollTo("settingLabel_naturalGrowthSlope"); UI.Layout()
        local l = label:GetAbsoluteLayoutForHitTest()
        UI.HandlePointerMove(UI.PointerEvent.new("PointerMove", {pointerId = 0, pointerType = "mouse", x = -20, y = -20}))
        local target = UI.FindWidgetAt(l.x + l.w / 2, l.y + l.h / 2)
        print(string.format("[设置悬浮命中] w=%g h=%g id=%s", l.w, l.h, tostring(target and target.props.id)))
        UI.HandlePointerMove(UI.PointerEvent.new("PointerMove", {pointerId = 0, pointerType = "mouse",
            x = (l.x + l.w / 2) * UI.GetScale(), y = (l.y + l.h / 2) * UI.GetScale()}))
        Check(Ctx().tips.active and Ctx().tips.active.widget == label, "参数名真实命中并开始悬浮计时")
    end,
    [85] = function()
        Check(Ctx().tips.popup ~= false, "滚动区域内参数悬浮说明")
        Screenshot("tooltip"); Ctx().tips:Hide()
        Bottom(); Click("settingsMigration")
        Check(Ctx().panel == "settings_migration", "迁移公式子页")
    end,
    [95] = function()
        Screenshot("migration"); Type("migrationRate", "12")
        Click("settingsBack"); Bottom(); Click("settingsCompetition")
        Check(Ctx().panel == "settings_competition", "制度公式子页")
    end,
    [105] = function()
        Screenshot("competition"); Type("replacementRate", "0")
        Click("settingsBack"); Click("settingsSave")
        Check(Ctx().world == world, "保存只返回重开草稿")
        Click("restartSameSeed")
        local cfg = Ctx().world.config
        Check(Ctx().world.generation == 0 and not Ctx().modalOpen and Ctx().seed == world.seed, "同种子重开应用")
        Check(cfg.naturalGrowthSlope == 4 and cfg.naturalGrowthRate == .2 and cfg.migrationRate == .12 and cfg.replacementRate == 0, "主窗口和子页参数全部应用")
        Check(S.VerifyReplay(Ctx().world), "自定义规则重放")
        Click("openSettings"); Bottom()
    end,
    [115] = function()
        Screenshot("applied")
        OriginDebug.ClosePanel()
        originalScale, originalViewport = UI.GetScale(), UI.GetViewportSize
        UI.SetScale(1.8)
        UI.GetViewportSize = function() return 780, 420 end
        local View = require("OriginView")
        View.Build(Ctx()); Ctx().root:SetStyle({width = 780, height = 420}); View.Resize(Ctx())
        Click("openSettings"); ScrollTo("populationCurve")
    end,
    [125] = function()
        Screenshot("compact")
        local l = Find("sheetCard"):GetAbsoluteLayout()
        Check(l.w <= 732 and l.h <= 372, "小屏窗口受视口约束")
        Click("settingsClose")
        UI.GetViewportSize = originalViewport; UI.SetScale(originalScale)
        originalViewport = nil
        OriginDebug.Restart(20261002, {})
        stopped = true
        print(string.format("[设置验收完成] %d项，已恢复默认地图和参数。", checks))
    end,
}
function Start()
    GameStart()
    UnsubscribeFromEvent("Update")
    SubscribeToEvent("Update", "OriginSettingsAcceptanceUpdate")
end
---@param eventType string
---@param eventData UpdateEventData
function OriginSettingsAcceptanceUpdate(eventType, eventData)
    GameUpdate(eventType, eventData)
    if stopped then return end
    frame = frame + 1
    if not steps[frame] then return end
    local ok, err = pcall(steps[frame])
    if not ok then
        stopped = true
        if originalViewport then UI.GetViewportSize = originalViewport; UI.SetScale(originalScale) end
        print("[设置验收失败] " .. tostring(err))
    end
end
