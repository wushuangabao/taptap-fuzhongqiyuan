-- 独立真实运行时检查；通过 UI 指针分发触发悬浮，正式入口不加载。
require("main")
local GameStart, GameUpdate = Start, HandleUpdate
local UI = require("urhox-libs/UI")
local cases = {
    {id = "layer_quality", text = "生活品质：颜色越亮，生活用品越充足。"},
    {id = "layer_population", text = "人口密度：颜色越深，人口越多。放大地图可查看人口数值。"},
    {id = "layer_institution", text = "制度分布：青绿为探索型，沙金为动员型；金色边框表示保护。"},
}
local frame, index, elapsed, done = 0, 1, 0, false

local function Move(x, y)
    local scale = UI.GetScale()
    UI.HandlePointerMove(UI.PointerEvent.new("PointerMove", {
        pointerId = 0, pointerType = "mouse", x = x * scale, y = y * scale,
    }))
end

local function Hover(ctx)
    UI.Layout()
    Move(-20, -20)
    assert(not ctx.tips.popup, "离开按钮后提示应关闭")
    local widget = assert(ctx.root:FindById(cases[index].id))
    local box = widget:GetAbsoluteLayoutForHitTest()
    Move(box.x + box.w / 2, box.y + box.h / 2)
    assert(ctx.tips.active and ctx.tips.active.widget == widget, "指针命中应启动悬浮计时")
    assert(not ctx.tips.popup, "悬浮提示应等待停留而非立即出现")
    elapsed = 0
end

function Start()
    GameStart()
    UnsubscribeFromEvent("Update")
    SubscribeToEvent("Update", "OriginTipsAcceptanceUpdate")
end

local function Check(eventData)
    frame = frame + 1
    local ctx = OriginDebug.GetGame()
    if frame < 20 then return end
    if frame == 20 then Hover(ctx); return end
    elapsed = elapsed + math.min(0.25, eventData:GetFloat("TimeStep"))
    if elapsed < 0.65 then return end
    local popup = assert(ctx.tips.popup, "正式更新应在停留后显示提示") --[[@as Panel]]
    local label = popup:GetChildren()[1] --[[@as Label]]
    assert(label:GetText() == cases[index].text, "提示正文必须完整保留，且不含旧标记说明")
    local image = Image()
    assert(graphics:TakeScreenShot(image))
    assert(image:SavePNG("tooltip-preserved-" .. cases[index].id .. ".png"))
    print("[悬浮提示验收] " .. cases[index].id .. "：" .. label:GetText())
    index = index + 1
    if index <= #cases then Hover(ctx); return end
    Move(-20, -20)
    assert(not ctx.tips.popup)
    done = true
    print("[悬浮提示验收完成] 三个图层提示均通过真实UI命中、停留显示、离开关闭检查")
end

function OriginTipsAcceptanceUpdate(eventType, eventData)
    GameUpdate(eventType, eventData)
    if done then return end
    local ok, failure = pcall(Check, eventData)
    if not ok then
        done = true
        print("[悬浮提示验收失败] " .. tostring(failure))
    end
end
