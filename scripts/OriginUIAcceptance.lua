-- 本地界面验收入口：在真实 UI 树上注入指针，模拟不同安全区与像素密度。
-- 此文件不由正式游戏加载；截图只代表模拟设备布局，不代表真机验收。
require("main")
local GameStart = Start
local UI = require("urhox-libs/UI")
local View = require("OriginView")
local Camera = require("OriginCamera")
local frame = 0
local checks = 0
local scenarios = {
    {name = "landscape", w = 960, h = 470, scale = 1.6, left = 44, right = 44, top = 0, bottom = 20, menu = 54},
    {name = "portrait", w = 430, h = 780, scale = 1, left = 0, right = 0, top = 44, bottom = 34, menu = 88},
    {name = "compact", w = 780, h = 420, scale = 1.8, left = 32, right = 32, top = 0, bottom = 18, menu = 40},
}
---@type table
local scenario = scenarios[1]

local function Check(condition, message)
    assert(condition, "[UI验收失败] " .. message)
    checks = checks + 1
    print("[UI验收通过] " .. message)
end

local function Near(a, b) return math.abs(a - b) < 0.01 end

local function Pointer(kind, id, x, y, touch)
    local event = UI.PointerEvent.new("Pointer" .. kind, {pointerId = id,
        pointerType = touch and "touch" or "mouse", button = MOUSEB_LEFT,
        x = x * UI.GetScale(), y = y * UI.GetScale()})
    UI.HandlePointerEvent(event)
end

local function Click(id)
    UI.Layout()
    local widget = assert(OriginDebug.GetGame().root:FindById(id), id)
    local l = widget:GetAbsoluteLayoutForHitTest()
    Pointer("Down", 0, l.x + l.w / 2, l.y + l.h / 2)
    Pointer("Up", 0, l.x + l.w / 2, l.y + l.h / 2)
end

local function SetViewport(index)
    scenario = scenarios[index]
    local s = scenario
    UI.SetScale(s.scale)
    -- 替身只存在于验收进程，正式代码始终读取真实平台数据。
    GetSafeAreaInsets = function() return Rect(s.left * s.scale, s.top * s.scale, s.right * s.scale, s.bottom * s.scale) end
    sdk = {GetNativeExitMenuRect = function() return {bottom = s.menu * s.scale / graphics.height} end}
    UI.GetViewportSize = function() return s.w, s.h end
    local ctx = OriginDebug.GetGame()
    ctx.root:SetStyle({width = s.w, height = s.h})
    View.Resize(ctx)
    UI.Layout()
end

local function Configure(index)
    SetViewport(index)
    local ctx = OriginDebug.GetGame()
    View.Build(ctx)
    ctx.root:SetStyle({width = scenario.w, height = scenario.h})
    UI.Layout()
end

local function SafeBounds(id)
    local w = assert(OriginDebug.GetGame().root:FindById(id), id)
    local l = w:GetAbsoluteLayoutForHitTest()
    Check(l.x >= scenario.left and l.x + l.w <= scenario.w - scenario.right + 1 and
        l.y >= math.max(scenario.top, scenario.menu) and l.y + l.h <= scenario.h - scenario.bottom + 1,
        scenario.name .. " · " .. id .. " 位于刘海/胶囊安全区内")
    return l
end

local function ExerciseOrientation()
    local ctx = OriginDebug.GetGame()
    local map = ctx.root:FindById("worldMap") --[[@as OriginMap]]
    local zoom, center = map.camera.zoom, map.camera.centerX
    local generation, selected = ctx.world.generation, ctx.selectedIndex
    Check(ctx.portraitBlocked and not ctx.root:FindById("safe").props.visible, "竖屏隐藏全部游戏操作")
    Check(ctx.root:FindById("orientationGuard").props.visible, "竖屏仅显示旋转提示")
    SafeBounds("rotateTitle")
    ctx.phase, ctx.accumulator, ctx.ticksRemaining = "simulation", 0, 8
    -- 只模拟 HandleUpdate 使用的事件访问器。
    local updateEvent = {GetFloat = function() return 0.25 end} --[[@as UpdateEventData]]
    for _ = 1, 10 do HandleUpdate("Update", updateEvent) end
    Check(ctx.world.generation == generation and ctx.accumulator == 0, "竖屏时停止世代演进")
    OriginDebug.Help()
    Check(not ctx.modalOpen, "竖屏不允许打开游戏操作弹窗")
    SetViewport(1)
    Check(not ctx.portraitBlocked and ctx.root:FindById("safe").props.visible, "转回横屏恢复界面")
    Check(map.camera.zoom == zoom and map.camera.centerX == center and ctx.selectedIndex == selected,
        "旋转设备保留地图倍率、位置与选区")
    ctx.phase, ctx.accumulator, ctx.ticksRemaining = "decision", 0, 0
    View.Refresh(ctx)
    OriginDebug.OpenPanel("trends")
    SetViewport(2)
    Check(not ctx.modalOpen, "切成竖屏会关闭弹窗并清理手势")
end

local function Exercise()
    local ctx = OriginDebug.GetGame()
    local map = ctx.root:FindById("worldMap") --[[@as OriginMap]]
    local rng, generation, selected = ctx.world.rng.state, ctx.world.generation, ctx.selectedIndex
    SafeBounds("hudStats"); SafeBounds("functionTools"); SafeBounds("mapZoom"); SafeBounds("inspector"); SafeBounds("actionPanel")
    SafeBounds("journey"); SafeBounds("technologyToggle")
    local l = SafeBounds("worldMap")
    Check(l.w >= 300 and l.h >= 160 and l.w / l.h < 2.8, scenario.name .. " · 地图拥有较方正的可视空间")
    Check(not ctx.root:FindById("sheetLayer"), "开局不显示弹窗")
    local cx, cy = l.x + l.w / 2, l.y + l.h / 2
    map:SetZoom(3)
    local before = map:Geometry()
    local ax, ay = cx + 15, cy - 12
    UI.HandleMouseMove(ax * UI.GetScale(), ay * UI.GetScale())
    UI.HandleWheel(0, 1)
    local after = map:Geometry()
    Check(map.camera.zoom > 3, "鼠标滚轮放大地图")
    Check(Near((ax - before.x) / before.cw, (ax - after.x) / after.cw) and
        Near((ay - before.y) / before.ch, (ay - after.y) / after.ch), "滚轮缩放保持鼠标下的地块位置")
    local slider = ctx.root:FindById("mapZoom") --[[@as Slider]]
    Check(Near(slider:GetValue(), map.camera.zoom), "滚轮与缩放滑块同步")
    local sl = slider:GetAbsoluteLayoutForHitTest()
    Pointer("Down", 0, sl.x + 12, sl.y + sl.h / 2)
    Pointer("Move", 0, sl.x + sl.w * 0.7, sl.y + sl.h / 2)
    Pointer("Up", 0, sl.x + sl.w * 0.7, sl.y + sl.h / 2)
    Check(map.camera.zoom > 4 and Near(slider:GetValue(), map.camera.zoom), "实际拖动滑块可缩放且不选地图")
    map:SetZoom(2.5)
    Pointer("Down", 11, cx - 40, cy, true)
    Pointer("Down", 29, cx + 40, cy, true)
    Pointer("Move", 11, cx - 60, cy, true)
    Pointer("Move", 29, cx + 60, cy, true)
    Check(Near(map.camera.zoom, 3.75), "不同触点ID的双指张合按距离缩放")
    Pointer("Up", 11, cx - 60, cy, true)
    Pointer("Move", 29, cx + 65, cy + 5, true)
    Pointer("Up", 29, cx + 65, cy + 5, true)
    Check(ctx.selectedIndex == selected, "双指缩放及单指离开不会误选地块")
    local oldY = map.camera.centerY
    Pointer("Down", 0, cx, cy)
    Pointer("Move", 0, cx + 30, cy + 24)
    Pointer("Up", 0, cx + 30, cy + 24)
    Check(map.camera.centerY < oldY and ctx.selectedIndex == selected, "拖动平移不会触发点击")
    Pointer("Down", 18, cx, cy, true)
    Pointer("Cancel", 18, cx, cy, true)
    Pointer("Up", 18, cx, cy, true)
    Check(next(map.pointers) == nil and ctx.selectedIndex == selected, "系统取消触摸后清理手势")
    map:SetZoom(4)
    local centerBefore = map.camera.centerY
    Pointer("Down", 11, cx - 40, cy, true); Pointer("Down", 29, cx + 40, cy, true)
    Pointer("Move", 11, cx - 40, cy + 20, true); Pointer("Move", 29, cx + 40, cy + 20, true)
    Check(Near(map.camera.zoom, 4) and map.camera.centerY < centerBefore, "双指同向拖动平移且不改变最终倍率")
    Pointer("Up", 11, cx - 40, cy + 20, true); Pointer("Up", 29, cx + 40, cy + 20, true)
    Camera.Pan(map.camera, l, 24, 16, 100000, -100000)
    local edge = map:Geometry()
    Check((edge.w <= l.w or (edge.x <= l.x + 1 and edge.x + edge.w >= l.x + l.w - 1)) and
        (edge.h <= l.h or (edge.y <= l.y + 1 and edge.y + edge.h >= l.y + l.h - 1)), "极端平移仍能看到地图，不会拖丢")
    map:SetZoom(100); Check(map.camera.zoom == Camera.MAX_ZOOM, "缩放上限有效")
    map:SetZoom(-5); Check(map.camera.zoom == Camera.MIN_ZOOM, "缩放下限有效")
    Check(Camera.Detail(15) == 1 and Camera.Detail(30) == 2 and Camera.Detail(60) == 3, "按地块显示尺寸切换三级细节")
    map:SetZoom(3)
    local b = map:Geometry()
    local x = math.floor((cx - b.x) / b.cw) + 1
    local y = math.floor((cy - b.y) / b.ch) + 1
    Pointer("Down", 0, cx, cy); Pointer("Up", 0, cx, cy)
    Check(ctx.selectedIndex == (y - 1) * ctx.world.config.width + x, "放大后点击选区准确")
    Click("resetMap")
    Check(map.camera.zoom == 1 and map.camera.centerX == 0.5 and map.camera.centerY == 0.5, "全图按钮还原相机")
    Check(ctx.world.rng.state == rng and ctx.world.generation == generation, "所有视图操作不改变模拟随机数和世代")
    local a1 = SafeBounds("action_agriculture")
    local a3 = SafeBounds("action_foodUp")
    local a4 = SafeBounds("action_foodDown")
    local a6 = SafeBounds("action_protect")
    Check(Near(a1.y, a3.y) and Near(a4.y, a6.y) and a4.y > a1.y, "六个干预按钮固定为两排")
    Check(not ctx.root:FindById("mapLegend") and not ctx.root:FindById("actionDescription"), "按钮说明不占据固定布局")
    Check(ctx.root:FindById("cellPosition").props.text == string.format("(%02d, %02d)", x, y), "地图点选实时更新常驻详情")
    local migration = ctx.showMigration
    Click("migrationToggle")
    Check(ctx.showMigration ~= migration, "迁移光点勾选框切换显示")
    Click("migrationToggle")
    local technology = ctx.showTechnology
    Click("technologyToggle")
    Check(ctx.showTechnology ~= technology, "技术传播显示开关独立生效")
    Click("technologyToggle")
    -- 鼠标停留显示，离开即消失；长按只看说明，松手不执行干预。
    UI.HandleMouseMove((a1.x + a1.w / 2) * UI.GetScale(), (a1.y + a1.h / 2) * UI.GetScale())
    ctx.tips:Update(0.4); UI.Layout()
    Check(ctx.root:FindById("buttonTip") ~= nil, "鼠标悬停显示 Tips")
    SafeBounds("buttonTip")
    UI.HandleMouseMove(cx * UI.GetScale(), cy * UI.GetScale())
    Check(not ctx.root:FindById("buttonTip"), "鼠标离开隐藏 Tips")
    local previousAction = ctx.action
    Pointer("Down", 41, a1.x + a1.w / 2, a1.y + a1.h / 2, true)
    ctx.tips:Update(0.6); UI.Layout()
    Check(ctx.root:FindById("buttonTip") ~= nil, "手指长按显示 Tips")
    SafeBounds("buttonTip")
    Pointer("Up", 41, a1.x + a1.w / 2, a1.y + a1.h / 2, true)
    Check(ctx.action == previousAction and not ctx.root:FindById("buttonTip"), "长按松手不误选行动")
    Pointer("Down", 41, a1.x + a1.w / 2, a1.y + a1.h / 2, true)
    Pointer("Up", 41, a1.x + a1.w / 2, a1.y + a1.h / 2, true)
    Check(ctx.action == "agriculture", "短按仍正常选择干预")
    OriginDebug.Choose("")
    Click("openTrends"); UI.Layout()
    local sheet = SafeBounds("sheetCard")
    Check(not ctx.root:FindById("closePanel"), "弹窗没有收起按钮")
    local zoom, chosen = map.camera.zoom, ctx.selectedIndex
    UI.HandleMouseMove((sheet.x + sheet.w / 2) * UI.GetScale(), (sheet.y + sheet.h / 2) * UI.GetScale())
    UI.HandleWheel(0, -1)
    Check(map.camera.zoom == zoom, "弹窗滚轮不会穿透缩放地图")
    Pointer("Down", 0, sheet.x + 25, sheet.y + 22); Pointer("Up", 0, sheet.x + 25, sheet.y + 22)
    Check(ctx.modalOpen, "点击弹窗内部保持打开")
    Pointer("Down", 0, sheet.x - 10, sheet.y + sheet.h / 2); Pointer("Up", 0, sheet.x - 10, sheet.y + sheet.h / 2)
    Check(not ctx.modalOpen and ctx.selectedIndex == chosen, "点击弹窗外关闭且不误选地图")
    ctx.speed = 1; View.Refresh(ctx)
    for _, speed in ipairs({2, 4, 1}) do
        Click("speed"); UI.Layout()
        Check(ctx.speed == speed and not ctx.modalOpen and not ctx.root:FindById("sheetLayer"), "点击直接切换倍率且不弹窗")
        Check(ctx.root:FindById("speedValue"):GetText() == tostring(speed) .. "×", "按钮同步显示当前倍率")
    end
    map:FrameInitialView()
    Check(map.camera.zoom >= 1 and map.camera.zoom <= 2.5, "开局局部视野使用适度缩放")
end

local function Screenshot(suffix)
    -- 截图由运行时 -screenshot / -screenshot-frame 输出；脚本不写绝对路径。
    print("[UI截图检查点] " .. scenario.name .. suffix)
end

function Start()
    GameStart()
    OriginDebug.GetGame().tipsClosed = true
    Configure(1)
    SubscribeToEvent("Update", "UIAcceptanceUpdate")
end

function UIAcceptanceUpdate(eventType, eventData)
    frame = frame + 1
    if frame == 5 then Exercise()
    elseif frame == 8 then Screenshot("")
    elseif frame == 10 then
        local ctx = OriginDebug.GetGame()
        local l = ctx.root:FindById("action_craft"):GetAbsoluteLayout()
        UI.HandleMouseMove((l.x + l.w / 2) * UI.GetScale(), (l.y + l.h / 2) * UI.GetScale())
        ctx.tips:Update(0.4)
    elseif frame == 13 then Screenshot("-popup"); OriginDebug.ClosePanel()
    elseif frame == 15 then
        local map = OriginDebug.GetGame().root:FindById("worldMap") --[[@as OriginMap]]
        map:SetZoom(5)
    elseif frame == 18 then Screenshot("-detail")
    elseif frame == 20 then SetViewport(2)
    elseif frame == 25 then ExerciseOrientation()
    elseif frame == 28 then Screenshot("")
    elseif frame == 30 then OriginDebug.OpenPanel("trends")
    elseif frame == 33 then Screenshot("-popup"); OriginDebug.ClosePanel()
    elseif frame == 35 then Configure(3)
    elseif frame == 40 then Exercise()
    elseif frame == 43 then Screenshot("")
    elseif frame == 45 then OriginDebug.OpenPanel("trends")
    elseif frame == 48 then Screenshot("-actions")
    elseif frame == 50 then print(string.format("[UI验收] 完成 %d 项检查。", checks)) end
end
