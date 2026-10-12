-- 独立真实窗口验收入口；正式游戏不加载。截图读取真实 backbuffer，并写入项目 savedata。
require("main")
local GameStart = Start
require("OriginLocalMilestonesAcceptance")
local UI = require("urhox-libs/UI")
local View = require("OriginView")
local S = require("OriginSimulation")
local frame, checks, screenshots, screenshotFailures = 0, 0, 0, 0
local stopped = false
local plainIndex, mountainIndex = 1, 1

local function Check(value, message)
    assert(value, "[Runtime验收失败] " .. message)
    checks = checks + 1
    print("[Runtime验收通过] " .. message)
end

local function Screenshot(name)
    local filename = "runtime-v17-" .. name .. ".png"
    local ok, failure = pcall(function()
        local captured = Image()
        assert(graphics:TakeScreenShot(captured), "TakeScreenShot 返回 false")
        assert(captured.width > 0 and captured.height > 0, "截图尺寸无效")
        assert(captured:SavePNG(filename), "SavePNG 返回 false")
        screenshots = screenshots + 1
        print(string.format("[Runtime截图已保存] %s %dx%d savedata相对路径；须读取图片后判断视觉结果",
            filename, captured.width, captured.height))
    end)
    if not ok then
        screenshotFailures = screenshotFailures + 1
        print("[Runtime截图失败] " .. filename .. " " .. tostring(failure) .. "；视觉结果 UNDETERMINED")
    end
end

local function CheckMap()
    local world = OriginDebug.GetGame().world
    local counts = {plain = 0, hill = 0, mountain = 0}
    local expected = S.BuildNeighbors(world.width, world.height)
    for i, cell in ipairs(world.cells) do
        assert(counts[cell.terrainKind], "地图只能包含三类陆地")
        counts[cell.terrainKind] = counts[cell.terrainKind] + 1
        assert(cell.population > 0 and cell.landCapacity > 0)
        assert(#world.neighbors[i] == #expected[i])
        for k, j in ipairs(assert(expected[i])) do assert(world.neighbors[i][k] == j) end
        if cell.terrainKind == "plain" then plainIndex = i end
        if cell.terrainKind == "mountain" then mountainIndex = i end
    end
    Check(counts.plain * 5 > #world.cells * 3, "平原严格超过60%")
    Check(counts.mountain * 20 < #world.cells * 3, "山地严格低于15%")
    Check(true, "所有格子有人口，完整保留四邻域")
    Check(world.config.terrainPlainCapacity == 1.5 and world.config.terrainMountainCapacity == 0.5,
        "平原和山地软承载系数分别为1.5和0.5")
end

local function Select(index)
    local world = OriginDebug.GetGame().world
    OriginDebug.Select((index - 1) % world.config.width + 1, (index - 1) // world.config.width + 1)
    UI.Layout()
end

local function AdvanceAcceptance()
    for _ = 1, 5 do LocalMilestonesAcceptanceUpdate() end
end

local function DeclineAndKeepHistory()
    local ctx = OriginDebug.GetGame()
    local history = {}
    for i, event in ipairs(ctx.localProgress.history) do history[i] = event end
    OriginDebug.ClosePanel()
    for _, cell in ipairs(ctx.world.cells) do
        cell.agriculture, cell.craft, cell.foodShare, cell.institution = 0.1, 0.1, 0.5, "mobilize"
    end
    S.RefreshMetrics(ctx.world)
    View.OnGeneration(ctx); View.Refresh(ctx)
    Check(ctx.world.metrics[ctx.selectedIndex].foodRatio < 1, "验收夹具已转为缺粮和制度衰退状态")
    Check(#history == 3 and #ctx.localProgress.history == 3
        and ctx.localProgress.history[1] == history[1] and ctx.localProgress.history[2] == history[2]
        and ctx.localProgress.history[3] == history[3], "当前状态衰退仍保留首次完成的三类历史")
    OriginDebug.OpenPanel("trends"); UI.Layout()
    Check(ctx.root:FindById("localEvent_food") and ctx.root:FindById("localEvent_technology")
        and ctx.root:FindById("localEvent_exploration"), "衰退后真实文明进程仍展示三条成果")
end

local steps = {
    [10] = function() CheckMap(); Screenshot("default-map") end,
    [20] = function()
        local map = OriginDebug.GetGame().root:FindById("worldMap") --[[@as OriginMap]]
        map:SetZoom(1)
    end,
    [30] = function() Screenshot("whole-map") end,
    [40] = function() Select(plainIndex) end,
    [50] = function() Screenshot("plain-detail") end,
    [60] = function() Select(mountainIndex) end,
    [70] = function() Screenshot("mountain-detail") end,
    [80] = AdvanceAcceptance,
    [90] = function() Screenshot("milestones-history") end,
    [100] = DeclineAndKeepHistory,
    [110] = function() Screenshot("milestones-after-decline") end,
    [120] = AdvanceAcceptance,
    [130] = function() Screenshot("milestones-compact") end,
    [140] = AdvanceAcceptance,
    [150] = function()
        Screenshot("restarted")
        print(string.format("[Runtime验收完成] 附加逻辑%d项；截图已保存%d张、失败%d张。另检查局部成果14项日志。",
            checks, screenshots, screenshotFailures))
        stopped = true
    end,
}

function Start()
    local ok, failure = pcall(function()
        GameStart()
        SubscribeToEvent("Update", "OriginRuntimeAcceptanceUpdate")
        print("[Runtime验收开始] 真实窗口渲染；前半段默认地图，后半段复用明确里程碑夹具。")
    end)
    if not ok then
        stopped = true
        print("[Runtime验收失败] 启动 " .. tostring(failure))
    end
end

function OriginRuntimeAcceptanceUpdate()
    if stopped then return end
    frame = frame + 1
    if not steps[frame] then return end
    local ok, failure = pcall(steps[frame])
    if not ok then
        stopped = true
        print(string.format("[Runtime验收失败] frame=%d %s；停止后续步骤", frame, tostring(failure)))
    end
end
