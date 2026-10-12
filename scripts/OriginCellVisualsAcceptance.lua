-- 独立真实窗口检查入口。正式main不加载；固定夹具只用于检查图形表达。
require("main")
local GameStart = Start
local GameUpdate = HandleUpdate
local UI = require("urhox-libs/UI")
local View = require("OriginView")
local S = require("OriginSimulation")
local V = require("OriginCellVisuals")
local frame, stopped = 0, false

local function Screenshot(name)
    local captured = Image()
    assert(graphics:TakeScreenShot(captured), "无法读取backbuffer")
    assert(captured:SavePNG("map-without-markers-" .. name .. ".png"), "截图保存失败")
    print("[地块信息图截图] " .. name)
end

local function Fixture()
    local ctx = OriginDebug.GetGame()
    ctx.world = S.New(1, {width = 6, height = 2, regionSize = 1, explorationAreas = 0, terrainEnabled = false})
    local world = ctx.world
    world.regions, world.cellRegionIds, world.baselineCraft = {}, {}, 1
    local population = {8, 20, 35, 50, 70, 95}
    ---@type number[]
    local food = {}
    for _, threshold in ipairs(V.FoodThresholds) do food[#food + 1] = threshold + 0.005 end
    local craft = {0.2, 0.5, 1.0, 1.5, 2.0, 3.0}
    for _, cell in ipairs(world.cells) do
        local column = cell.x
        cell.population, cell.landCapacity, cell.foodShare = population[column], 40, 0.5
        local denominator = 1 + cell.population / cell.landCapacity
        -- 第一行展示1—6档，第二行农业、玫瑰全满，对照不同人口档位。
        local f, c = cell.y == 1 and food[column] or food[6], cell.y == 1 and craft[column] or 3
        cell.agriculture, cell.craft = f * denominator / 0.5, c * denominator / 0.5
    end
    S.RefreshMetrics(world)
    for i, cell in ipairs(world.cells) do
        local m = world.metrics[i]
        local actual = V.State(cell.population, m.foodRatio, m.craftPerCapita, world.baselineCraft)
        assert(actual.foodBlocks == (cell.y == 1 and cell.x or 6), "农业夹具档位不符")
        if cell.y == 2 and cell.x == 6 then
            assert(actual.foodBlocks == 6 and actual.roses == 6 and actual.houses == 6, "满档夹具不符")
        end
    end
    ctx.selectedIndex, ctx.regionX, ctx.regionY = 1, 1, 1
    View.Build(ctx); UI.Layout()
end

local function ShortfallFixture()
    Fixture()
    local ctx = OriginDebug.GetGame()
    local world = ctx.world
    local food = {0.90, 0.97, 0.99, 1.0, 1.02, 1.05}
    local blocks = {3, 3, 3, 4, 4, 4}
    for i, value in ipairs(food) do
        local cell = world.cells[i]
        cell.population = 40
        cell.agriculture = value * 2 / cell.foodShare
    end
    S.RefreshMetrics(world)
    for i in ipairs(food) do
        local m = world.metrics[i]
        local value = V.State(40, m.foodRatio, m.craftPerCapita, world.baselineCraft)
        assert(value.foodBlocks == blocks[i], "颜色修复不能改变数量刻度")
        if m.foodRatio < 1 then
            assert(value.foodColor[1] > value.foodColor[2], "缺粮不应显绿")
        elseif m.foodRatio >= 1.02 then
            assert(value.foodColor[2] > value.foodColor[1], "盈余应渐绿")
        else
            assert(value.foodColor[1] == 225 and value.foodColor[2] == 174, "临界应为黄")
        end
    end
    ctx.selectedIndex, ctx.regionX, ctx.regionY = 3, 3, 1
    View.Refresh(ctx)
    print("[温饱渐变验收] 0.90/0.97/0.99保持暖色，1.0为黄，1.02/1.05快速渐绿")
end

local function ScaleFixture(width)
    local ctx = OriginDebug.GetGame()
    local map = assert(ctx.root:FindById("worldMap")) --[[@as OriginMap]]
    local before = map:Geometry()
    -- 仅检查入口设置精确格宽；不改变正式相机的缩放范围。
    map.camera.zoom = map.camera.zoom * width / before.cw
    local after = map:Geometry()
    assert(math.abs(after.cw - width) < 0.001)
    print("[地块满档格宽] " .. tostring(width))
end

local steps = {
    [20] = function() Screenshot("default") end,
    [30] = Fixture,
    [50] = function() Screenshot("comparison") end,
    [60] = function() ScaleFixture(22) end,
    [70] = function() Screenshot("width22") end,
    [80] = function() ScaleFixture(42) end,
    [90] = function() Screenshot("width42") end,
    [100] = function() ScaleFixture(60) end,
    [110] = function() Screenshot("width60") end,
    [120] = ShortfallFixture,
    [140] = function() Screenshot("shortfall") end,
    [150] = function() OriginDebug.Restart(); UI.Layout() end,
    [170] = function() Screenshot("restored"); print("[地块信息图验收完成]"); stopped = true end,
}

function Start()
    GameStart()
    UnsubscribeFromEvent("Update")
    SubscribeToEvent("Update", "OriginCellVisualsAcceptanceUpdate")
end

function OriginCellVisualsAcceptanceUpdate(eventType, eventData)
    -- 验收完成后仍保留正常界面更新，避免预览窗口的悬浮提示失效。
    GameUpdate(eventType, eventData)
    if stopped then return end
    frame = frame + 1
    if not steps[frame] then return end
    local ok, failure = pcall(steps[frame])
    if not ok then stopped = true; print("[地块信息图验收失败] " .. tostring(failure)) end
end
