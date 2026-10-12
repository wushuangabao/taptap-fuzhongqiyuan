-- 独立真实窗口验收入口，正式main不加载；通过真实UI点击、输入和截图验收种子重开。
require("main")
local GameStart = Start
local UI = require("urhox-libs/UI")
local S = require("OriginSimulation")
local frame, checks = 0, 0
local stopped = false
local initial = ""

local function Check(value, message)
    assert(value, "[种子验收失败] " .. message)
    checks = checks + 1
    print("[种子验收通过] " .. message)
end

local function Click(id)
    UI.Layout()
    local widget = assert(OriginDebug.GetGame().root:FindById(id), id)
    local l = widget:GetAbsoluteLayoutForHitTest()
    for _, kind in ipairs({"Down", "Up"}) do
        UI.HandlePointerEvent(UI.PointerEvent.new("Pointer" .. kind, {
            pointerId = 0, pointerType = "mouse", button = MOUSEB_LEFT,
            x = (l.x + l.w / 2) * UI.GetScale(), y = (l.y + l.h / 2) * UI.GetScale(),
        }))
    end
end

local function Signature(world)
    local parts = {}
    for i, cell in ipairs(world.cells) do
        parts[i] = string.format("%s/%d/%.9f/%.9f/%.9f/%s", cell.terrainKind, world.cellRegionIds[i],
            cell.population, cell.agriculture, cell.craft, cell.institution)
    end
    return table.concat(parts, ";")
end

local function Screenshot(name, cropId)
    local captured = Image()
    assert(graphics:TakeScreenShot(captured), "截图失败")
    if cropId then
        local l = OriginDebug.GetGame().root:FindById(cropId):GetAbsoluteLayout()
        local scale = UI.GetScale()
        captured = captured:GetSubimage(IntRect(math.floor(l.x * scale), math.floor(l.y * scale),
            math.ceil((l.x + l.w) * scale), math.ceil((l.y + l.h) * scale)))
    end
    assert(captured:SavePNG("restart-seed-" .. name .. ".png"), "截图写入失败")
    print("[种子验收截图] restart-seed-" .. name .. ".png")
end

local function CheckReset(seed)
    local ctx = OriginDebug.GetGame()
    Check(ctx.seed == seed and ctx.world.seed == seed, "世界与当前种子同步：" .. seed)
    Check(ctx.world.generation == 0 and ctx.world.round == 0 and #ctx.world.actions == 0
        and ctx.phase == "decision" and not ctx.paused and not ctx.modalOpen
        and ctx.ticksRemaining == 0 and ctx.accumulator == 0 and #ctx.localProgress.history == 0,
        "重开清空世代、行动、演进和成果历史")
    local expected = S.Baseline(seed)
    Check(ctx.baseline[1].craftPerCapita == expected[1].craftPerCapita
        and ctx.baseline[#ctx.baseline].craftPerCapita == expected[#expected].craftPerCapita,
        "无干预对照来自当前地图种子")
end

local steps = {
    [10] = function()
        initial = Signature(OriginDebug.GetGame().world)
        Screenshot("icon", "openRestart")
        Click("openRestart")
        local ctx = OriginDebug.GetGame()
        Check(ctx.modalOpen and ctx.root:FindById("currentMapSeed"):GetText() == tostring(ctx.world.seed),
            "点击重开按钮显示实际地图种子")
    end,
    [20] = function()
        Screenshot("dialog")
        local ctx = OriginDebug.GetGame()
        local world, baseline, rng = ctx.world, ctx.baseline, ctx.world.rng.state
        local field = ctx.root:FindById("restartSeedInput") --[[@as TextField]]
        for _, value in ipairs({"", "abc", "1.5", "-1", "1e3", "0x10", "2147483648", string.rep("9", 100)}) do
            field:SetValue(value)
            Click("restartWithSeed")
            Check(ctx.modalOpen and ctx.world == world and ctx.baseline == baseline
                and ctx.world.rng.state == rng and ctx.root:FindById("seedInputHint"):GetText():find("种子无效"),
                "非法输入保留当前地图与进度：" .. value)
        end
    end,
    [30] = function()
        local ctx = OriginDebug.GetGame()
        Click("restartSeedInput")
        local field = ctx.root:FindById("restartSeedInput") --[[@as TextField]]
        field:SelectAll()
        UI.HandleTextInput("0")
        Check(field:GetValue() == "0", "真实输入事件可编辑种子")
        Click("restartWithSeed")
        CheckReset(0)
        Check(Signature(ctx.world) ~= initial, "指定新种子重新生成地图")
        Click("openRestart")
    end,
    [40] = function()
        Screenshot("zero")
        local ctx = OriginDebug.GetGame()
        local field = ctx.root:FindById("restartSeedInput") --[[@as TextField]]
        field:SetValue(" 2147483647 ")
        field.props.onSubmit(field, field:GetValue())
        CheckReset(2147483647)
        local signature = Signature(ctx.world)
        OriginDebug.Choose("agriculture"); OriginDebug.Confirm(); OriginDebug.Advance()
        Click("openRestart"); Click("restartSameSeed")
        CheckReset(2147483647)
        Check(Signature(ctx.world) == signature, "同种子重开复现初始地图与数值")
        Click("openRestart"); Click("restartRandomSeed")
        CheckReset(ctx.seed)
        Check(ctx.seed > 0 and ctx.seed < 2147483647, "重新随机种子生成不同的有效种子")
        Click("openRestart")
    end,
    [50] = function()
        Screenshot("random")
        for _, kind in ipairs({"Down", "Up"}) do
            UI.HandlePointerEvent(UI.PointerEvent.new("Pointer" .. kind, {
                pointerId = 0, pointerType = "mouse", button = MOUSEB_LEFT,
                x = 10 * UI.GetScale(), y = 10 * UI.GetScale(),
            }))
        end
        Check(not OriginDebug.GetGame().modalOpen, "点击弹窗外可取消")
        OriginDebug.Restart(20261002)
        print(string.format("[种子验收完成] %d项；已恢复默认地图。", checks))
        stopped = true
    end,
}

function Start()
    GameStart()
    SubscribeToEvent("Update", "OriginRestartAcceptanceUpdate")
end

function OriginRestartAcceptanceUpdate()
    if stopped then return end
    frame = frame + 1
    if not steps[frame] then return end
    local ok, failure = pcall(steps[frame])
    if not ok then stopped = true; print("[种子验收失败] " .. tostring(failure)) end
end
