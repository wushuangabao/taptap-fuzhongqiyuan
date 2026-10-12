-- 本地真实窗口专项验收，正式 main 不加载。正式概率，固定种子15验证两种制度的结果差异。
require("main")
local GameStart, GameUpdate = Start, HandleUpdate
local UI = require("urhox-libs/UI")
local S = require("OriginSimulation")
local View = require("OriginView")
local OriginalViewport, OriginalScale = UI.GetViewportSize, UI.GetScale()
local frame, stopped = 0, false

local function LabelText(id)
    local label = assert(OriginDebug.GetGame().root:FindById(id)) --[[@as Label]]
    return label:GetText()
end

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

local function CheckLayout()
    UI.Layout()
    local root = OriginDebug.GetGame().root
    local panel = assert(root:FindById("actionPanel")):GetAbsoluteLayoutForHitTest()
    local w, h = UI.GetViewportSize()
    assert(panel.x >= 0 and panel.y >= 0 and panel.x + panel.w <= w + 0.5 and panel.y + panel.h <= h + 0.5)
    for _, id in ipairs({"regionLand", "improvementResult", "confirm", "skipRound", "followRecommendation"}) do
        local l = assert(root:FindById(id)):GetAbsoluteLayoutForHitTest()
        assert(l.h > 0 and l.y >= panel.y and l.y + l.h <= panel.y + panel.h + 0.5, id .. " clipped")
        assert(l.x >= panel.x and l.x + l.w <= panel.x + panel.w + 0.5, id .. " too wide")
    end
    local result = assert(root:FindById("improvementResult")):GetAbsoluteLayoutForHitTest()
    local confirm = assert(root:FindById("confirm")):GetAbsoluteLayoutForHitTest()
    assert(result.y + result.h < confirm.y + 0.5, "结果与按钮重叠")
end

local function SelectInstitution(institution)
    local ctx = OriginDebug.GetGame()
    for _, cell in ipairs(ctx.world.cells) do
        if cell.institution == institution then
            OriginDebug.Select(cell.x, cell.y)
            assert(LabelText("regionLand"):find(institution == "explore" and "30%%" or "10%%"))
            return
        end
    end
    error("找不到测试制度")
end

local function Attempt(action, institution)
    OriginDebug.Restart(15)
    local ctx = OriginDebug.GetGame()
    -- 连续重开只隔离通知残留，避免前一案例的 Toast 遮住下一案例；不替换 UI 或规则。
    UI.Toast.GetGlobal():DismissAll()
    ctx.tipsClosed = true
    SelectInstitution(institution)
    local cell, beforeDraws = ctx.world.cells[ctx.selectedIndex], ctx.world.rng.draws
    local before = cell[action]
    Click("action_" .. action); Click("confirm")
    assert(ctx.phase == "simulation" and ctx.world.round == 1)
    ctx.paused = true
    local outcome = ctx.world.actions[1].improvements[1]
    -- 种子15首次抽签约 0.263，动员失败、探索成功；未修改随机流或参数。
    local success = institution == "explore"
    assert(outcome.succeeded == success and ctx.world.rng.draws == beforeDraws + 1)
    assert(ctx.world.protectionLeft == 3 and cell.protectionTicks == 0)
    assert(cell[action] == before * (success and (action == "craft" and 1.15 or 1.12) or 1))
    assert(LabelText("improvementResult"):find(success and "改良成功" or "未成功"))
    print(string.format("[概率改良检查] %s %s roll=%.9f success=%s", action, institution, outcome.roll, tostring(success)))
    CheckLayout()
end

local function CompleteRound()
    local ctx = OriginDebug.GetGame()
    local result = LabelText("improvementResult")
    ctx.paused = false
    for _ = 1, 5 do OriginDebug.Advance() end
    assert(ctx.phase == "decision" and ctx.world.generation == 5)
    assert(LabelText("improvementResult") == result)
    assert(S.VerifyReplay(ctx.world))
    CheckLayout()
end

local function Capture(name)
    local image = Image()
    assert(graphics:TakeScreenShot(image))
    assert(image:SavePNG("improvements-v191-" .. name .. ".png"))
    print("[概率改良截图] " .. name)
end

local steps = {
    [20] = function() SelectInstitution("mobilize"); CheckLayout() end,
    [30] = function() Capture("mobilize") end,
    [40] = function() Attempt("craft", "mobilize") end,
    [55] = function() Capture("craft-failed") end,
    [65] = CompleteRound,
    [80] = function() Capture("failed-round-complete") end,
    [90] = function() Attempt("agriculture", "mobilize"); CompleteRound() end,
    [105] = function() Capture("agriculture-failed") end,
    [115] = function() Attempt("agriculture", "explore"); CompleteRound() end,
    [130] = function() Capture("agriculture-succeeded") end,
    [140] = function() Attempt("craft", "explore"); CompleteRound() end,
    [155] = function() Capture("craft-succeeded") end,
    [165] = function()
        UI.Toast.GetGlobal():DismissAll()
        UI.SetScale(1.8)
        UI.GetViewportSize = function() return 780, 420 end
        local ctx = OriginDebug.GetGame()
        View.Build(ctx); ctx.root:SetStyle({width = 780, height = 420})
        View.Resize(ctx); CheckLayout()
    end,
    [180] = function() Capture("compact") end,
    [190] = function()
        UI.Toast.GetGlobal():DismissAll()
        UI.SetScale(OriginalScale); UI.GetViewportSize = OriginalViewport
        OriginDebug.Restart(20261002); SelectInstitution("explore"); CheckLayout()
    end,
    [205] = function() Capture("explore"); print("[概率改良验收] PASS formal 10/30; all four outcomes; replay; wide/compact"); stopped = true end,
}

function Start()
    GameStart()
    UnsubscribeFromEvent("Update")
    SubscribeToEvent("Update", "OriginImprovementAcceptanceUpdate")
end

function OriginImprovementAcceptanceUpdate(eventType, eventData)
    GameUpdate(eventType, eventData)
    if stopped then return end
    frame = frame + 1
    if steps[frame] then
        local ok, err = pcall(steps[frame])
        if not ok then stopped = true; print("[概率改良验收] FAIL " .. tostring(err)) end
    end
end
