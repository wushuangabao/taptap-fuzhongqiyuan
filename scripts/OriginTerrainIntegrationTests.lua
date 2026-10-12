-- 地形与正式经济/迁移模型的集成测试；地形启用，解析状态显式固定。
local S = require("OriginSimulation")
local Terrain = require("OriginTerrain")
local Config = require("OriginConfig")
local Tests = {}

local function near(a, b)
    assert(math.abs(a - b) < 1e-9, string.format("%.15g != %.15g", a, b))
end

local function fixture(width)
    return S.New(13, {width = width, height = 1, explorationAreas = 0, terrainEnabled = true})
end

---@param cell OriginCell
---@param kind OriginTerrainKind
---@param utility number
---@param config OriginParameters
---@param f number?
local function setCell(cell, kind, utility, config, f)
    cell.population, cell.landCapacity = 100, 100
    cell.baseLandCapacity = 100
    cell.foodShare = f or 0.5
    cell.agriculture = 2 / cell.foodShare
    cell.craft = (math.exp(utility) - 1) * 2 / (1 - cell.foodShare)
    cell.terrainKind = kind
    cell.migrationMultiplier = Terrain.Profile(kind, config).migrationMultiplier
end

function Tests.Run()
    local report = {passed = 0, failed = 0, results = {}, ok = false}
    local function test(name, fn)
        local ok, err = pcall(fn)
        report.results[#report.results + 1] = {name = name, passed = ok, error = not ok and tostring(err) or nil}
        if ok then report.passed = report.passed + 1 else report.failed = report.failed + 1 end
        print("[地形集成] " .. (ok and "通过 " or "失败 ") .. name .. (ok and "" or (": " .. tostring(err))))
    end
    test("地形按倍率缩放容量与人口，保持同一经济格初始人均产出", function()
        local on, off = S.New(20261002, {}), S.New(20261002, {terrainEnabled = false})
        for i, cell in ipairs(on.cells) do
            local original = off.cells[i]
            local p = Terrain.Profile(cell.terrainKind, on.config)
            near(cell.landCapacity, original.landCapacity * p.capacityMultiplier)
            near(cell.population, original.population * p.capacityMultiplier)
            near(on.metrics[i].foodRatio, off.metrics[i].foodRatio)
            near(on.metrics[i].craftPerCapita, off.metrics[i].craftPerCapita)
            assert(cell.agriculture == original.agriculture and cell.craft == original.craft)
        end
        assert(on.rng.state == off.rng.state and on.rng.draws == off.rng.draws)
    end)
    test("软承载不截断超载人口，也不禁止食物充足时出生", function()
        local world = fixture(1)
        local cell = world.cells[1]
        cell.population = cell.landCapacity * 2
        cell.agriculture, cell.foodShare = 12, 0.5
        local before = cell.population
        S.NaturalGrowth(world)
        assert(cell.population > before and cell.population > cell.landCapacity)
        cell.agriculture = 1
        local crowded = S.Metrics(cell, world.config).foodRatio
        cell.population = cell.population / 2
        assert(S.Metrics(cell, world.config).foodRatio > crowded)
    end)
    test("九种起终点地形流量均取两端较慢效率", function()
        for _, from in ipairs({"plain", "hill", "mountain"}) do
            for _, to in ipairs({"plain", "hill", "mountain"}) do
                local world = fixture(2)
                setCell(world.cells[1], from, 0.4, world.config)
                setCell(world.cells[2], to, 0.9, world.config)
                local factor = math.min(Terrain.Profile(from, world.config).migrationMultiplier,
                    Terrain.Profile(to, world.config).migrationMultiplier)
                local flows, deltas = S.Migrate(world)
                local expected = 100 * 0.24 * 0.4 / 1.4 * factor
                assert(#flows == 1 and flows[1].from == 1 and flows[1].to == 2)
                near(flows[1].amount, expected); near(flows[1].terrainFactor, factor)
                near(deltas[1].outgoing, expected); near(deltas[2].incoming, expected)
                near(world.cells[1].population + world.cells[2].population, 200)
                assert(world.cells[1].population > 0)
            end
        end
    end)
    test("一条山路减慢不会把未迁出人口转分给另一条路", function()
        local world = fixture(3)
        setCell(world.cells[1], "plain", 0.9, world.config)
        setCell(world.cells[2], "plain", 0.4, world.config)
        setCell(world.cells[3], "mountain", 0.9, world.config)
        local flows = S.Migrate(world)
        assert(#flows == 2)
        local normal = 100 * 0.24 * 0.8 / 1.8 / 2
        local mountain = normal * Config.terrainMountainMigration
        near(flows[1].amount, normal); near(flows[2].amount, mountain)
        near(world.cells[2].population, 100 - normal - mountain)
        near(world.cells[1].population + world.cells[2].population + world.cells[3].population, 300)
    end)
    test("文化混合使用地形折减后的实际迁入量", function()
        local world = fixture(2)
        setCell(world.cells[1], "plain", 0.4, world.config, 0.3)
        setCell(world.cells[2], "mountain", 0.9, world.config, 0.7)
        local flows = S.Migrate(world)
        local incoming = flows[1].amount
        near(world.cells[2].foodShare, 0.7 + 0.5 * incoming / (100 + incoming) * (0.3 - 0.7))
    end)
    test("减速迁移仍来自同一快照，无同世代二次搬迁", function()
        local world = fixture(3)
        setCell(world.cells[1], "mountain", 0.2, world.config)
        setCell(world.cells[2], "hill", 0.6, world.config)
        setCell(world.cells[3], "plain", 1.0, world.config)
        local flows = S.Migrate(world)
        assert(#flows == 2)
        local base = 100 * 0.24 * 0.3 / 1.3
        near(flows[1].amount, base * Config.terrainMountainMigration)
        near(flows[2].amount, base * Config.terrainHillMigration)
    end)
    test("迁移快照与世代历史保存地形，整轮可精确重放", function()
        local world = S.New(20261002)
        assert(S.ApplyAction(world, "craft", 10, 6))
        for _ = 1, Config.generationsPerRound do S.Tick(world) end
        local delta = world.lastReport.deltas[1]
        assert(delta.before.terrainKind == world.cells[1].terrainKind)
        assert(delta.before.migrationMultiplier == world.cells[1].migrationMultiplier)
        assert(S.VerifyReplay(world))
        world.terrainVersion = "unknown"
        local valid, reason = S.VerifyReplay(world)
        assert(not valid and reason == "terrain_mismatch")
    end)
    test("地形参数拒绝负承载、零通行与超过100%的迁移效率", function()
        assert(not pcall(S.New, 1, {terrainMountainCapacity = 0}))
        assert(not pcall(S.New, 1, {terrainHillMigration = 0}))
        assert(not pcall(S.New, 1, {terrainPlainMigration = 1.01}))
        assert(not pcall(S.Replay, 1, {}, {modelVersion = "origin-1.2.0"}))
    end)
    report.ok = report.failed == 0
    return report
end

return Tests
