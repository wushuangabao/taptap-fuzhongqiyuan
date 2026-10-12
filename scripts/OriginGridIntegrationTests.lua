-- 无障碍四邻域回归：使用正式模型检查地形不再删除邻接边或附加产出。
local S = require("OriginSimulation")
local Terrain = require("OriginTerrain")
local Tests = {}

local function near(a, b) assert(math.abs(a - b) < 1e-9) end

local function fixture()
    local world = S.New(13, {width = 3, height = 1, explorationAreas = 0,
        mobilizeAgricultureGrowth = 0, exploreAgricultureGrowth = 0, mobilizeCraftGrowth = 0, exploreCraftGrowth = 0, replacementRate = 1})
    for i, cell in ipairs(world.cells) do
        cell.terrainKind = ({"plain", "mountain", "hill"})[i]
        cell.migrationMultiplier = Terrain.Profile(cell.terrainKind).migrationMultiplier
        cell.population, cell.landCapacity = 100, 100
        cell.agriculture, cell.craft, cell.foodShare, cell.institution = 4, 2, 0.5, "mobilize"
    end
    return world
end

function Tests.Run()
    local report = {passed = 0, failed = 0, ok = false, results = {}}
    local function test(name, fn)
        local ok, err = pcall(fn)
        report.results[#report.results + 1] = {name = name, passed = ok, error = not ok and tostring(err) or nil}
        if ok then report.passed = report.passed + 1 else report.failed = report.failed + 1 end
        print("[四邻域集成] " .. (ok and "通过 " or "失败 ") .. name .. (ok and "" or tostring(err)))
    end
    test("多种子和边界尺寸所有格子均保留几何四邻域", function()
        for _, size in ipairs({{1,1}, {1,16}, {24,1}, {3,3}, {24,16}}) do
            for seed = 1, 32 do
                local w, h = size[1], size[2]
                local world = S.New(seed * 7919, {width = w, height = h, explorationAreas = 0})
                for i, cell in ipairs(world.cells) do
                    assert(cell.population > 0 and cell.landCapacity > 0)
                    assert(cell.terrainKind == "plain" or cell.terrainKind == "hill" or cell.terrainKind == "mountain")
                    local expected, actual = {}, {}
                    if cell.x > 1 then expected[i-1] = true end
                    if cell.x < w then expected[i+1] = true end
                    if cell.y > 1 then expected[i-w] = true end
                    if cell.y < h then expected[i+w] = true end
                    for _, j in ipairs(assert(world.neighbors[i])) do
                        assert(expected[j] and not actual[j], "多余、重复、对角或跨边邻居")
                        actual[j] = true
                    end
                    for j in pairs(expected) do assert(actual[j], "地形删除了相邻边") end
                end
            end
        end
    end)
    test("每格经济严格使用基础公式，无邻岸产出加成", function()
        local world = S.New()
        for _, cell in ipairs(world.cells) do
            local metric = S.Metrics(cell, world.config)
            local labor = cell.population / (1 + cell.population / cell.landCapacity)
            near(metric.food, cell.agriculture * cell.foodShare * labor)
            near(metric.craft, cell.craft * (1 - cell.foodShare) * labor)
        end
    end)
    test("人口可迁入山地，但同世代不穿越中间格", function()
        local world = fixture()
        world.cells[2].craft = 20
        local flows = S.Migrate(world)
        assert(#flows == 2 and world.cells[2].population > 100)
        for _, flow in ipairs(flows) do assert(flow.to == 2 and flow.amount > 0); near(flow.terrainFactor, 0.4) end
        near(world.cells[1].population + world.cells[2].population + world.cells[3].population, 300)
    end)
    test("技术逐格经过山地传播，同世代不跨两格", function()
        local world = fixture()
        world.cells[1].craft = 20
        S.GrowTechnology(world)
        near(world.cells[2].craft, 2.9); near(world.cells[3].craft, 2)
        S.GrowTechnology(world)
        assert(world.cells[3].craft > 2)
    end)
    test("制度可进入山地且保持同步结算", function()
        local world = fixture()
        world.cells[1].craft, world.cells[1].institution = 1000, "explore"
        world.rng = S.NewRandom(1)
        local changes = S.Compete(world)
        assert(#changes == 1 and changes[1].index == 2)
        assert(world.cells[2].institution == "explore" and world.cells[3].institution == "mobilize")
    end)
    test("独立保护只覆盖所选一格且不改工艺", function()
        local world = S.New()
        local before = {}
        for i, cell in ipairs(world.cells) do before[i] = cell.craft end
        assert(S.ApplyAction(world, "protect", 1, 1))
        for i, cell in ipairs(world.cells) do
            local inside = cell.x == 1 and cell.y == 1
            near(cell.craft, before[i])
            assert(cell.protectionTicks == (inside and world.config.protectionDuration or 0))
        end
        for _ = 1, world.config.generationsPerRound do S.Tick(world) end
        assert(S.VerifyReplay(world))
    end)
    test("旧版河流配置和行动记录明确拒绝", function()
        assert(not pcall(S.New, 1, {riversEnabled = true}))
        assert(not pcall(S.New, 1, {riverbankProductionBonus = 0.25}))
        local world = S.New()
        assert(S.ApplyAction(world, "craft", 1, 1))
        world.actions[1].version, world.actions[1].modelVersion = "origin-1.6.0", "origin-1.6.0"
        assert(not pcall(S.Replay, world.seed, world.actions))
    end)
    report.ok = report.failed == 0
    return report
end
return Tests
