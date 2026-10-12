-- 《富种起源》核心模型测试。require 不执行测试；显式调用 Tests.Run()。
local S = require("OriginSimulation")
local Config = require("OriginConfig")
local Tests = {}

---@class OriginTestResult
---@field name string
---@field passed boolean
---@field error string?

---@class OriginTestReport
---@field passed integer
---@field failed integer
---@field total integer
---@field ok boolean
---@field results OriginTestResult[]

---@class OriginTestCase
---@field name string
---@field run fun()

---@param condition boolean
---@param message string?
local function check(condition, message)
    assert(condition, message or "断言失败")
end

---@param actual number
---@param expected number
---@param tolerance number?
local function near(actual, expected, tolerance)
    local limit = tolerance or 1e-10
    assert(S.IsFinite(actual) and math.abs(actual - expected) <= limit,
        string.format("实际 %.17g，期望 %.17g，容差 %.3g", actual, expected, limit))
end

---@param value number
local function finite(value)
    check(S.IsFinite(value), "出现 NaN 或无限数")
end

---@param width integer
---@param height integer
---@param overrides table?
---@return OriginWorld
local function fixture(width, height, overrides)
    -- 微型公式夹具显式关闭传播、保证改良成功并采用短回合；正式概率另有端到端测试。
    local config = { width = width, height = height, explorationAreas = 0, regionSize = 3,
        generationsPerRound = 5, protectionDuration = 5, technologyDiffusion = 0, terrainEnabled = false,
        mobilizeImprovementProbability = 1, exploreImprovementProbability = 1 }
    for key, value in pairs(overrides or {}) do config[key] = value end
    local world = S.New(12345, config)
    for _, cell in ipairs(world.cells) do
        cell.population, cell.landCapacity = 40.0, 40.0
        cell.agriculture, cell.craft, cell.foodShare = 4.0, 2.0, 0.5
        cell.institution, cell.protectionTicks = Config.mobilizeInstitution, 0
    end
    S.RefreshMetrics(world)
    return world
end

-- 调整 A 保持 s=1；通过 B 给定精确效用，便于隔离迁移阶段。
---@param cell OriginCell
---@param utility number
---@param foodShare number?
local function setUtility(cell, utility, foodShare)
    local f = foodShare or cell.foodShare
    cell.foodShare = f
    local denominator = 1.0 + cell.population / cell.landCapacity
    cell.agriculture = denominator / f
    cell.craft = (math.exp(utility) - 1.0) * denominator / (1.0 - f)
end

---@param world OriginWorld
---@return number
local function population(world)
    local sum = 0.0
    for _, cell in ipairs(world.cells) do sum = sum + cell.population end
    return sum
end

---@param actual any
---@param expected any
local function same(actual, expected)
    check(type(actual) == type(expected), "重放类型不同")
    if type(actual) ~= "table" then check(actual == expected, "重放数值不同") return end
    for key, value in pairs(actual) do same(value, expected[key]) end
    for key in pairs(expected) do check(actual[key] ~= nil, "重放缺少字段") end
end

---@type OriginTestCase[]
local cases = {}

---@param name string
---@param run fun()
local function add(name, run)
    cases[#cases + 1] = { name = name, run = run }
end

add("集中参数与初始 384 格、分散探索区", function()
    check(Config.width == 24 and Config.height == 16 and Config.rounds == 50
        and Config.generationsPerRound == 5 and Config.regionSize == 1)
    check(Config.technologyDiffusion == 0.05 and Config.protectionDuration == 5)
    check(Config.defaultSeed == 20261002 and Config.protectionUses == 3)
    local world = S.New()
    check(#world.cells == 384 and #world.metrics == 384 and #world.neighbors == 384)
    check(world.generation == 0 and world.round == 0 and #world.history == 1)
    check(world.lastReport == world.history[1] and world.history[1].initial)
    local explore = 0
    for i, cell in ipairs(world.cells) do
        check(cell.x == (i - 1) % 24 + 1 and cell.y == (i - 1) // 24 + 1)
        check(cell.baseLandCapacity >= 32 and cell.baseLandCapacity <= 48)
        local terrain = require("OriginTerrain").Profile(cell.terrainKind, world.config)
        near(cell.landCapacity, cell.baseLandCapacity * terrain.capacityMultiplier)
        check(cell.agriculture >= 2.8 and cell.agriculture <= 3.2)
        check(cell.craft >= 1.8 and cell.craft <= 2.2 and cell.foodShare >= 0.5 and cell.foodShare <= 0.65)
        if S.IsHabitable(cell) then
            local noise = cell.population / (cell.landCapacity * (cell.agriculture * cell.foodShare - 1.0))
            check(noise >= 0.9 and noise <= 1.1 and cell.population > 0)
        else
            check(cell.population == 0 and cell.landCapacity == 0 and cell.institution == "none")
        end
        if cell.institution == "explore" then explore = explore + 1 end
    end
    check(explore == 16 and #world.explorationAreas == 4)
    for i, a in ipairs(world.explorationAreas) do
        check(a.size == 2)
        for y = a.y, a.y + 1 do
            for x = a.x, a.x + 1 do check(world.cells[(y - 1) * 24 + x].institution == "explore") end
        end
        for j = i + 1, #world.explorationAreas do
            local b = world.explorationAreas[j]
            check(a.x + a.size + 1 < b.x or b.x + b.size + 1 < a.x
                or a.y + a.size + 1 < b.y or b.y + b.size + 1 < a.y, "探索区未分散")
        end
    end
    same(world.cells, S.New().cells)
    check(world.config ~= Config, "世界不能持有可变的全局配置引用")
end)

add("单格公式与人口平衡", function()
    local world = fixture(1, 1)
    local cell = world.cells[1]
    cell.agriculture, cell.craft, cell.foodShare = 3.0, 2.0, 0.6
    cell.population = cell.landCapacity * (cell.agriculture * cell.foodShare - 1.0)
    local m = S.Metrics(cell)
    local labor = cell.population / (1.0 + cell.population / cell.landCapacity)
    near(m.L, labor)
    near(m.F, cell.agriculture * cell.foodShare * labor)
    near(m.C, cell.craft * (1.0 - cell.foodShare) * labor)
    near(m.s, m.F / cell.population)
    near(m.c, m.C / cell.population)
    near(m.s, 1.0)
    near(m.U, math.log(1.0 + m.c))
    near(m.P, m.F + 0.5 * m.C)
    near(S.NaturalGrowth(world)[1], 0.0)
    near(S.Tanh(0), 0)
    near(S.Tanh(1000), 1)
    near(S.Tanh(-1000), -1)
end)

add("自然增减符号与农业工艺差异", function()
    local world = fixture(3, 1)
    world.cells[1].agriculture = 5.0
    world.cells[2].agriculture = 3.0
    local m = S.Metrics(world.cells[3])
    world.cells[3].craft = 10.0
    local crafted = S.Metrics(world.cells[3])
    near(crafted.foodRatio, m.foodRatio)
    check(crafted.craftPerCapita > m.craftPerCapita and crafted.utility > m.utility)
    local natural = S.NaturalGrowth(world)
    check(natural[1] > 0 and natural[2] < 0)
    near(natural[3], 0.0)
    near(natural[1], 40.0 * 0.50 * S.Tanh(0.5))
    near(natural[2], 40.0 * 0.50 * S.Tanh(-0.5))
    local hungry = S.Metrics(world.cells[2])
    near(hungry.U, math.log(1.0 + hungry.c) - 4.0 * math.max(0, 1.0 - hungry.s))
end)

add("迁移示例 6.857142857143", function()
    local world = fixture(2, 1)
    world.cells[1].population = 100.0
    setUtility(world.cells[1], 0.4)
    setUtility(world.cells[2], 0.9)
    local before = population(world)
    local flows, deltas = S.Migrate(world)
    check(#flows == 1 and flows[1].from == 1 and flows[1].to == 2)
    near(flows[1].utilityDifference, 0.4)
    near(flows[1].amount, 48.0 / 7.0)
    near(deltas[1].outgoing, 6.857142857142857)
    near(deltas[2].incoming, flows[1].amount)
    near(population(world), before)
end)

add("对称无流与迁移阻力", function()
    local world = fixture(3, 3)
    local before = population(world)
    local flows, deltas = S.Migrate(world)
    check(#flows == 0)
    for _, delta in ipairs(deltas) do near(delta.incoming, 0) near(delta.outgoing, 0) end
    near(population(world), before)
    local pair = fixture(2, 1)
    setUtility(pair.cells[1], 0.4)
    setUtility(pair.cells[2], 0.499)
    check(#S.Migrate(pair) == 0, "阻力内不能迁移")
    setUtility(pair.cells[2], 0.501)
    check(#S.Migrate(pair) == 1, "超过阻力应迁移")
    local without = fixture(2, 1, { migrationResistance = 0.0 })
    setUtility(without.cells[1], 0.4)
    setUtility(without.cells[2], 0.499)
    check(#S.Migrate(without) == 1)
end)

add("同步迁移、无二次迁移与全局守恒", function()
    local world = fixture(3, 1)
    setUtility(world.cells[1], 0.2)
    setUtility(world.cells[2], 1.3)
    setUtility(world.cells[3], 2.4)
    local flows, deltas = S.Migrate(world)
    check(#flows == 2)
    near(deltas[1].outgoing, 4.8)
    near(deltas[2].incoming, 4.8)
    near(deltas[2].outgoing, 4.8, 1e-9)
    near(world.cells[2].population, 40.0)
    near(population(world), 120.0)
    local random = S.New(9876)
    for _ = 1, 20 do
        local before = population(random)
        local _, changes = S.Migrate(random)
        near(population(random), before, 1e-8)
        local incoming, outgoing = 0.0, 0.0
        for i, delta in ipairs(changes) do
            if S.IsHabitable(random.cells[i]) then check(delta.outgoing < delta.populationBefore * 0.24)
            else check(delta.outgoing == 0 and delta.incoming == 0) end
            near(random.cells[i].population, delta.populationBefore + delta.incoming - delta.outgoing, 1e-10)
            incoming, outgoing = incoming + delta.incoming, outgoing + delta.outgoing
        end
        near(incoming, outgoing, 1e-9)
    end
end)

add("人口加权迁入文化与快照来源", function()
    local world = fixture(3, 1)
    setUtility(world.cells[1], 0.2, 0.3)
    setUtility(world.cells[2], 1.0, 0.5)
    setUtility(world.cells[3], 0.3, 0.8)
    local flows, deltas = S.Migrate(world)
    check(#flows == 2 and deltas[2].incoming > 0)
    local average = (deltas[1].outgoing * 0.3 + deltas[3].outgoing * 0.8) / deltas[2].incoming
    near(deltas[2].weightedIncomingF, average)
    near(world.cells[2].foodShare, 0.5 + 0.5 * deltas[2].incoming / world.cells[2].population * (average - 0.5))
    near(world.cells[1].foodShare, 0.3)
    near(world.cells[3].foodShare, 0.8)
    local chain = fixture(3, 1)
    setUtility(chain.cells[1], 0.2, 0.3)
    setUtility(chain.cells[2], 1.3, 0.5)
    setUtility(chain.cells[3], 2.4, 0.8)
    local chained, cultural = S.Migrate(chain)
    check(chain.cells[2].foodShare < 0.5)
    near(chained[2].sourceFoodShare, 0.5)
    near(cultural[3].weightedIncomingF, 0.5, 1e-9)
    near(chain.cells[3].foodShare, 0.8 + 0.5 * cultural[3].incoming / chain.cells[3].population * (0.5 - 0.8))
end)

add("两种制度技术增长与实力乘数", function()
    local world = fixture(2, 1)
    world.cells[2].institution = "explore"
    S.GrowTechnology(world)
    near(world.cells[1].agriculture, 4.0 * 1.002)
    near(world.cells[2].agriculture, 4.0 * 1.002)
    near(world.cells[1].craft, 2.0 * 1.002)
    near(world.cells[2].craft, 2.0 * 1.015)
    local mobilize = S.Metrics(world.cells[1])
    local explore = S.Metrics(world.cells[2])
    near(mobilize.power, mobilize.food + 0.5 * mobilize.craft)
    near(explore.power, 0.75 * (explore.food + 0.5 * explore.craft))
end)

add("竞争同步替代与习惯 80/20", function()
    local world = fixture(3, 1, { replacementRate = 1.0 })
    world.cells[1].craft, world.cells[1].foodShare = 1.0, 0.3
    world.cells[2].craft, world.cells[2].foodShare = 20.0, 0.5
    world.cells[3].craft, world.cells[3].foodShare = 1000.0, 0.8
    world.cells[1].institution, world.cells[2].institution, world.cells[3].institution = "mobilize", "explore", "mobilize"
    world.rng = S.NewRandom(1)
    local changes, attempts = S.Compete(world)
    check(#attempts == 2 and #changes == 2)
    check(world.cells[1].institution == "explore" and world.cells[2].institution == "mobilize")
    near(world.cells[1].foodShare, 0.8 * 0.3 + 0.2 * 0.5)
    near(world.cells[2].foodShare, 0.8 * 0.5 + 0.2 * 0.8)
    check(changes[1].index == 1 and changes[1].from == 2 and changes[1].newInstitution == "explore")
    near(changes[1].sourceFoodShare, 0.5)
    for _, attempt in ipairs(attempts) do
        near(attempt.probability, (attempt.neighborPower - attempt.ownPower) / (attempt.neighborPower + attempt.ownPower))
    end
end)

add("无意义同制度替代与最高邻居优先", function()
    local world = fixture(2, 1)
    world.cells[1].foodShare, world.cells[2].foodShare = 0.3, 0.7
    world.cells[2].craft = 100.0
    local before = world.cells[1].foodShare
    local draws = world.rng.draws
    local changes, attempts = S.Compete(world)
    check(#changes == 0 and #attempts == 0 and world.rng.draws == draws)
    near(world.cells[1].foodShare, before)
    local trio = fixture(3, 1)
    trio.cells[1].craft = 100.0
    trio.cells[3].craft, trio.cells[3].institution = 50.0, "explore"
    local _, tried = S.Compete(trio)
    for _, attempt in ipairs(tried) do check(attempt.index ~= 2, "不能绕过最高同制度邻居") end
end)

add("邻居并列使用固定种子随机", function()
    local world = fixture(3, 1)
    world.cells[1].craft, world.cells[3].craft = 20.0, 20.0
    world.cells[1].institution, world.cells[3].institution = "explore", "explore"
    local rng = S.NewRandom(987)
    local expectedFrom = S.RandomInteger(rng, 1, 2) == 1 and 1 or 3
    local expectedRoll = S.Random(rng)
    world.rng = S.NewRandom(987)
    local _, attempts = S.Compete(world)
    check(#attempts == 1 and attempts[1].from == expectedFrom)
    near(attempts[1].roll, expectedRoll)
    check(world.rng.draws == 2)
    local chosen = {}
    for seed = 1, 20 do
        local candidate = fixture(3, 1)
        candidate.cells[1].craft, candidate.cells[3].craft = 20.0, 20.0
        candidate.cells[1].institution, candidate.cells[3].institution = "explore", "explore"
        -- 第一抽的连续小种子都很接近零，先前进三次以测试两个方向。
        candidate.rng = S.NewRandom(seed)
        S.Random(candidate.rng) S.Random(candidate.rng) S.Random(candidate.rng)
        local _, tried = S.Compete(candidate)
        chosen[tried[1].from] = true
    end
    check(chosen[1] and chosen[3], "并列不能固定偏向同一方向")
end)

add("保护完整五次竞争，之后衰减", function()
    local world = fixture(2, 1)
    world.cells[2].craft, world.cells[2].institution = 100.0, "explore"
    world.cells[1].protectionTicks = 5
    local own, other = S.Metrics(world.cells[1]), S.Metrics(world.cells[2])
    local base = 0.2 * (other.P - own.P) / (other.P + own.P)
    for tick = 1, 6 do
        world.cells[1].institution, world.cells[1].foodShare = "mobilize", 0.5
        world.rng = S.NewRandom(100000)
        local _, attempts = S.Compete(world)
        check(#attempts == 1)
        check(attempts[1].protected == (tick <= 5))
        near(attempts[1].probability, tick <= 5 and base * 0.25 or base)
        S.DecayProtection(world)
        check(world.cells[1].protectionTicks == math.max(0, 5 - tick))
    end
end)

add("行动完整 3×3、边缘无裁切、参数倍率", function()
    local world = fixture(5, 5, { mobilizeAgricultureGrowth = 0.0, exploreAgricultureGrowth = 0.0, mobilizeCraftGrowth = 0.0, migrationRate = 0.0 })
    local valid, reason = S.ApplyAction(world, "agriculture", 3, 3)
    check(valid and reason == "ok" and world.round == 1 and world.generation == 0)
    for _, cell in ipairs(world.cells) do near(cell.agriculture, cell.x >= 3 and cell.y >= 3 and 4.0 * 1.12 or 4.0) end
    for _ = 1, 5 do S.Tick(world) end
    check(S.ApplyAction(world, "craft", 1, 1))
    for _, cell in ipairs(world.cells) do near(cell.craft, cell.x <= 3 and cell.y <= 3 and 2.0 * 1.15 or 2.0) end
    local round, draws = world.round, world.rng.draws
    for _, xy in ipairs({ {0, 1}, {1, 0}, {4, 3}, {3, 4}, {1.5, 1}, {-1, 1} }) do
        local ok, why = S.ValidateAction(world, "agriculture", xy[1], xy[2])
        check(not ok and why == "region_out_of_bounds")
        check(not S.ApplyAction(world, "agriculture", xy[1], xy[2]))
    end
    check(world.round == round and world.rng.draws == draws)
    check(not S.ValidateAction(world, "unknown", 1, 1))
    check(#world.actions == 2 and world.actions[1].seed == world.seed)
    check(world.actions[1].version == Config.modelVersion and world.actions[1].rngVersion == Config.rngVersion)
end)

add("习惯边界、无变化方向与全探索禁用", function()
    local world = fixture(3, 3)
    for _, cell in ipairs(world.cells) do cell.foodShare = 0.85 end
    local valid, reason = S.ValidateAction(world, "foodUp", 1, 1)
    check(not valid and reason == "no_change")
    check(S.ApplyAction(world, "foodDown", 1, 1))
    for _, cell in ipairs(world.cells) do near(cell.foodShare, 0.75) end
    local lower = fixture(3, 3)
    for _, cell in ipairs(lower.cells) do cell.foodShare = 0.25 end
    check(not S.ValidateAction(lower, "foodDown", 1, 1))
    lower.cells[1].foodShare = 0.26
    check(S.ApplyAction(lower, "foodDown", 1, 1))
    near(lower.cells[1].foodShare, 0.25)
    local institutions = fixture(3, 3)
    check(S.ApplyAction(institutions, "institution", 1, 1))
    for _, cell in ipairs(institutions.cells) do check(cell.institution == "explore") end
    local allExplore = fixture(3, 3)
    for _, cell in ipairs(allExplore.cells) do cell.institution = "explore" end
    local ok, why = S.ValidateAction(allExplore, "institution", 1, 1)
    check(not ok and why == "no_change")
    allExplore.cells[1].institution = "mobilize"
    check(S.ValidateAction(allExplore, "institution", 1, 1))
end)

add("保护不可附加到任何行动，拒绝后世界与随机数不变", function()
    for _, action in ipairs({"agriculture", "craft", "foodUp", "foodDown", "institution", "protect", "skip"}) do
        local world, before = fixture(3, 3), fixture(3, 3)
        local valid, reason = S.ApplyAction(world, action, 1, 1, true)
        check(not valid and reason == "invalid_protection")
        same(world, before)
    end
end)

add("独立保护三次、占用一轮与max延长", function()
    local world = fixture(3, 3)
    for use = 1, 3 do
        check(S.ApplyAction(world, "protect", 1, 1))
        check(world.protectionLeft == 3 - use)
        for _, cell in ipairs(world.cells) do check(cell.protectionTicks == 5) end
        if use < 3 then
            local valid, reason = S.ValidateAction(world, "protect", 1, 1)
            check(not valid and reason == "round_in_progress")
        end
        for _ = 1, 5 do S.Tick(world) end
    end
    local valid, reason = S.ValidateAction(world, "protect", 1, 1)
    check(not valid and reason == "no_protection_uses")
    local unchanged = fixture(3, 3)
    for _, cell in ipairs(unchanged.cells) do cell.institution = "explore" end
    local unchangedValid, unchangedReason = S.ValidateAction(unchanged, "institution", 1, 1)
    check(not unchangedValid and unchangedReason == "no_change")
    local extended = fixture(3, 3)
    extended.cells[1].protectionTicks = 8
    check(S.ApplyAction(extended, "protect", 1, 1))
    check(extended.cells[1].protectionTicks == 8 and extended.cells[2].protectionTicks == 5)
end)

add("单世代单格、报告拆分与回合不自动推进", function()
    local world = fixture(1, 1)
    world.cells[1].agriculture = 3.0
    local initialPopulation = world.cells[1].population
    local expectedNatural = initialPopulation * 0.50 * S.Tanh(-0.5)
    local report = S.Tick(world)
    check(world.generation == 1 and world.round == 0 and #world.history == 2)
    check(report == world.lastReport and report == world.history[2])
    check(#report.flows == 0 and #report.changes == 0 and #report.deltas == 1)
    near(report.deltas[1].natural, expectedNatural)
    near(report.deltas[1].naturalDecrease, -expectedNatural)
    near(report.deltas[1].incoming, 0) near(report.deltas[1].outgoing, 0)
    near(report.deltas[1].cultureChange, 0) near(report.deltas[1].institutionFoodChange, 0)
    near(world.cells[1].population, initialPopulation + expectedNatural)
    near(world.cells[1].agriculture, 3.0 * 1.002)
    near(world.cells[1].craft, 2.0 * 1.002)
    near(report.summary.population, world.cells[1].population)
    world.cells[1].population = 99.0
    near(report.deltas[1].after.population, initialPopulation + expectedNatural)
    near(report.deltas[1].before.population, initialPopulation)
end)

add("极小正人口不设置凭空下限", function()
    local world = fixture(1, 1)
    world.cells[1].population, world.cells[1].agriculture, world.cells[1].foodShare = 1e-100, 2.0, 0.25
    local report = S.Tick(world)
    check(world.cells[1].population > 0 and world.cells[1].population < 1e-100)
    near(report.deltas[1].incoming, 0)
    check(report.deltas[1].natural < 0)
    finite(S.Metrics(world.cells[1]).foodRatio)
end)

add("逐格报告分解与流量总量", function()
    local world = S.New(998877)
    for _ = 1, 5 do
        local report = S.Tick(world)
        local natural, incoming, outgoing = 0.0, 0.0, 0.0
        for _, delta in ipairs(report.deltas) do
            near(delta.populationChange, delta.natural + delta.incoming - delta.outgoing, 1e-9)
            near(delta.foodShareChange, delta.cultureChange + delta.institutionFoodChange, 1e-12)
            near(delta.natural, delta.naturalIncrease - delta.naturalDecrease)
            natural, incoming, outgoing = natural + delta.natural, incoming + delta.incoming, outgoing + delta.outgoing
        end
        near(report.summary.population - report.populationBefore, natural, 1e-8)
        near(incoming, outgoing, 1e-8)
        near(report.totalMigration, outgoing, 1e-9)
        near(report.populationAfterMigration, report.populationAfterNatural, 1e-8)
        local flowTotal = 0.0
        for _, flow in ipairs(report.flows) do
            check(flow.amount > 0 and math.abs(world.cells[flow.from].x - world.cells[flow.to].x)
                + math.abs(world.cells[flow.from].y - world.cells[flow.to].y) == 1)
            flowTotal = flowTotal + flow.amount
        end
        near(flowTotal, outgoing, 1e-8)
    end
end)

add("全局人口权重与固定 c0", function()
    local world = fixture(2, 1)
    world.cells[1].population, world.cells[1].agriculture, world.cells[1].craft = 10.0, 4.0, 10.0
    world.cells[1].institution = "explore"
    world.cells[2].population, world.cells[2].agriculture, world.cells[2].craft = 90.0, 4.0, 2.0
    world.baselineCraft = 0.5
    local a, b = S.Metrics(world.cells[1]), S.Metrics(world.cells[2])
    local statistics = S.Statistics(world)
    near(statistics.population, 100.0)
    near(statistics.craftPerCapita, (a.C + b.C) / 100.0)
    near(statistics.foodRatio, (a.F + b.F) / 100.0)
    near(statistics.exploreShare, 0.1)
    near(statistics.prosperousShare, 0.1)
    near(statistics.starvingShare, 0.9)
    check(math.abs(statistics.craftPerCapita - (a.c + b.c) * 0.5) > 0.1, "不能按格平均")
    local actual = S.New()
    local initial = actual.baselineCraft
    near(initial, S.Statistics(actual).craftPerCapita)
    check(S.ApplyAction(actual, "craft", 1, 1))
    for _ = 1, actual.config.generationsPerRound do S.Tick(actual) near(actual.baselineCraft, initial) end
    check(S.ApplyAction(actual, "foodDown", 1, 1))
    for _ = 1, actual.config.generationsPerRound do S.Tick(actual) near(actual.baselineCraft, initial) end
    near(actual.history[1].summary.baselineCraft, initial)
end)

add("连续五世代胜利、断 streak 与提前重放停止", function()
    local world = fixture(1, 1, { mobilizeAgricultureGrowth = 0.0, exploreAgricultureGrowth = 0.0, mobilizeCraftGrowth = 0.0 })
    world.baselineCraft = 0.25
    for generation = 1, 4 do S.Tick(world) check(not world.won and world.prosperousStreak == generation) end
    world.cells[1].craft = 0.5
    S.Tick(world)
    check(world.prosperousStreak == 0 and not world.won)
    world.cells[1].craft = 2.0
    for generation = 1, 5 do S.Tick(world) check(world.prosperousStreak == generation) end
    check(world.won and world.maxProsperousShare == 1.0)
    -- 第一次行动后 5 世代，第 2 次行动的第 1 世代达标；不再推进剩余四次。
    local cfg = { prosperousCraftMultiplier = 0.01, prosperousFoodRatio = 0.0, victoryStreak = 6, generationsPerRound = 5 }
    local replayed = S.Replay(42, {
        { action = "agriculture", x = 1, y = 1 }, { action = "craft", x = 1, y = 1 },
    }, cfg)
    check(replayed.won and replayed.generation == 6 and replayed.round == 2 and #replayed.history == 7)
    check(not S.ValidateAction(replayed, "craft", 1, 1))
end)

add("固定 RNG 已知向量与世界随机独立", function()
    local rng = S.NewRandom(1)
    S.Random(rng) check(rng.state == 16807)
    S.Random(rng) check(rng.state == 282475249)
    S.Random(rng) check(rng.state == 1622650073)
    check(rng.draws == 3)
    local zero = S.NewRandom(0)
    check(zero.state == 1)
    local a, b = S.New(-42), S.New(-42)
    same(a.cells, b.cells)
    local unrelated = S.New(99)
    for _ = 1, 3 do S.Tick(a) S.Tick(unrelated) S.Tick(b) end
    same(a.cells, b.cells) same(a.history, b.history) same(a.rng, b.rng)
end)

add("随机行动完整重放、版本与篡改验证", function()
    for _, seed in ipairs({ 20261002, 1, -98765 }) do
        local world = S.New(seed)
        local choice = S.NewRandom(seed + 17)
        local names = { "agriculture", "craft", "foodUp", "foodDown", "institution" }
        for _ = 1, 10 do
            local action = names[S.RandomInteger(choice, 1, #names)]
            local x, y = S.RandomInteger(choice, 1, world.width - world.config.regionSize + 1),
                S.RandomInteger(choice, 1, world.height - world.config.regionSize + 1)
            if not S.ValidateAction(world, action, x, y) then action = "craft" end
            check(S.ApplyAction(world, action, x, y))
            for _ = 1, world.config.generationsPerRound do if world.won then break end S.Tick(world) end
            if world.won then break end
        end
        local replayed = S.Replay(seed, world.actions)
        same(world.cells, replayed.cells) same(world.history, replayed.history) same(world.rng, replayed.rng)
        local valid, reason = S.VerifyReplay(world)
        check(valid and reason == "ok")
        local original = world.actions[1].rngVersion
        world.actions[1].rngVersion = "错误版本"
        check(not pcall(S.Replay, seed, world.actions))
        world.actions[1].rngVersion = original
        world.actions[1].generation = 1
        check(not pcall(S.Replay, seed, world.actions))
        world.actions[1].generation = 0
        world.cells[1].craft = world.cells[1].craft + 1.0
        check(not S.VerifyReplay(world))
    end
end)

add("250 世代有限性、baseline 与 summary 字段一致", function()
    for _, seed in ipairs({ 20261002, 1, 0, -100, 2147483647 }) do
        local world = S.New(seed)
        local keys = world.history[1].summary
        local limit = world.config.rounds * world.config.generationsPerRound
        for _ = 1, limit do
            local report = S.Tick(world)
            for key in pairs(keys) do check(report.summary[key] ~= nil, "统计字段缺失：" .. key) end
            for key in pairs(report.summary) do check(keys[key] ~= nil, "统计字段新增：" .. key) end
            for _, value in pairs(report.summary) do if type(value) == "number" then finite(value) end end
            for _, cell in ipairs(world.cells) do
                check(S.IsHabitable(cell) and cell.population > 0 or not S.IsHabitable(cell) and cell.population == 0)
                finite(cell.population) finite(cell.agriculture) finite(cell.craft) finite(cell.foodShare)
                check(cell.foodShare >= 0.25 and cell.foodShare <= 0.85)
            end
            near(report.migrationConservationError, 0, 1e-8)
        end
        check(world.generation == limit and world.round == 0 and #world.history == limit + 1 and #world.actions == 0)
        check(not pcall(S.Tick, world), "不允许越过世代上限")
        local baseline = S.Baseline(seed)
        check(#baseline == limit + 1 and baseline[1].generation == 0 and baseline[limit + 1].generation == limit)
        same(baseline[1], world.history[1].summary)
        same(baseline[limit + 1], world.history[limit + 1].summary)
    end
end)

add("四邻域固定边界、配置校验与行动上限", function()
    local neighbors = S.BuildNeighbors(3, 2)
    same(neighbors[1], {2, 4})
    same(neighbors[3], {2, 6})
    same(neighbors[5], {4, 6, 2})
    local isolated = S.BuildNeighbors(1, 1)
    check(#isolated[1] == 0)
    check(not pcall(S.New, 1, { width = 1, height = 1 }))
    check(not pcall(S.New, 1.25))
    check(not pcall(S.New, 1, { migrationRate = 1.0 }))
    check(not pcall(S.New, 1, { unknown = 1 }))
    local world = fixture(3, 3, { rounds = 1 })
    check(S.ApplyAction(world, "craft", 1, 1))
    check(not S.ApplyAction(world, "agriculture", 1, 1))
    for _ = 1, 5 do S.Tick(world) end
    check(world.round == 1 and world.generation == 5)
end)

add("观察期禁止额外行动且无隐式赠送回合", function()
    local world = fixture(3, 3)
    check(S.ApplyAction(world, "craft", 1, 1))
    local protected, actions, rng = world.protectionLeft, #world.actions, world.rng.state
    for generation = 0, 4 do
        check(world.generation == generation and world.round == 1)
        local valid, reason = S.ValidateAction(world, "protect", 1, 1)
        check(not valid and reason == "round_in_progress")
        check(not S.ApplyAction(world, "protect", 1, 1))
        check(world.protectionLeft == protected and #world.actions == actions and world.rng.state == rng)
        S.Tick(world)
        rng = world.rng.state
    end
    check(world.generation == 5 and world.round == 1)
    check(S.ApplyAction(world, "protect", 1, 1))
    check(world.round == 2 and world.generation == 5 and #world.actions == 2)
end)

add("正式单格边界与五世代保护、原子性和重放", function()
    local world = S.New()
    local before = world.cells[384].craft
    check(S.ApplyAction(world, "protect", 24, 16))
    check(world.round == 1 and world.generation == 0 and world.protectionLeft == 2)
    near(world.cells[384].craft, before)
    local covered = 0
    for _, cell in ipairs(world.cells) do if cell.protectionTicks == 5 then covered = covered + 1 end end
    check(covered == 1 and world.actions[1].action == "protect" and not world.actions[1].withProtection)
    for tick = 1, 5 do
        check(not S.ApplyAction(world, "protect", 23, 16))
        S.Tick(world)
        check(world.cells[384].protectionTicks == 5 - tick)
    end
    check(S.VerifyReplay(world))
    check(S.ValidateAction(world, "craft", 24, 16))
    check(not S.ValidateAction(world, "craft", 25, 16))
    check(not S.ValidateAction(world, "craft", 24, 17))
    check(S.ValidateAction(world, "protect", 1, 1))
    local blank = fixture(5, 5, {regionSize = 1, protectionDuration = 5})
    for _, cell in ipairs(blank.cells) do cell.institution = "explore" end
    check(not S.ApplyAction(blank, "institution", 1, 1))
    check(blank.protectionLeft == 3 and blank.round == 0 and #blank.actions == 0)
    check(blank.cells[1].protectionTicks == 0)
end)

add("正式六类行动只影响所选一格", function()
    for _, action in ipairs({"agriculture", "craft", "foodUp", "foodDown", "institution", "protect"}) do
        for _, position in ipairs({{1, 1}, {12, 8}, {24, 16}}) do
            local world = S.New()
            local x, y = position[1], position[2]
            local selected = (y - 1) * world.width + x
            world.cells[selected].institution = "mobilize"
            local before = S.New()
            check(S.ApplyAction(world, action, x, y))
            for i, cell in ipairs(world.cells) do
                if i ~= selected then same(cell, before.cells[i]) end
            end
            check(world.cells[selected].protectionTicks == (action == "protect" and 5 or 0))
            check(world.round == 1 and #world.actions == 1)
            check(not S.ApplyAction(world, "craft", x == 1 and 2 or 1, y), "同轮不能改干预另一格")
        end
    end
end)

add("正式50轮每轮5世代，第51次干预被拒绝", function()
    local world = S.New()
    for round = 1, 50 do
        check(S.ApplyAction(world, "craft", 1, 1))
        check(world.round == round and world.generation == (round - 1) * 5)
        for _ = 1, 5 do S.Tick(world) end
        check(not world.won, "本夹具应走完全部轮数")
        check(world.generation == round * 5)
    end
    check(#world.actions == 50 and #world.history == 251)
    local valid, reason = S.ApplyAction(world, "craft", 2, 1)
    check(not valid and reason == "generation_limit")
    check(world.round == 50 and #world.actions == 50)
    check(not pcall(S.Tick, world))
end)

add("邻格技术学习同步、不会单世代跨两格或消耗随机数", function()
    local world = fixture(4, 1, {technologyDiffusion = 0.05, mobilizeAgricultureGrowth = 0, exploreAgricultureGrowth = 0, mobilizeCraftGrowth = 0})
    for _, cell in ipairs(world.cells) do cell.agriculture, cell.craft = 2, 2 end
    world.cells[1].agriculture, world.cells[2].craft = 10, 10
    local draws = world.rng.draws
    local learning, flows = S.GrowTechnology(world)
    near(world.cells[1].agriculture, 10)
    near(world.cells[2].agriculture, 2.4)
    near(world.cells[3].agriculture, 2)
    near(world.cells[4].craft, 2)
    near(world.cells[1].craft, 2.4)
    near(world.cells[3].craft, 2.4)
    near(learning[2].agriculture, 0.4)
    check(#flows == 3 and world.rng.draws == draws)
    for _, flow in ipairs(flows) do check(math.abs(flow.from - flow.to) == 1) end
    local report = S.Tick(world)
    local delta = report.deltas[2]
    near(delta.agricultureChange, delta.agricultureLearned)
    check(not pcall(S.New, 1, {technologyDiffusion = 1.01}))
end)

add("短板按人口分为四类且互不重叠", function()
    local world = fixture(4, 1)
    world.baselineCraft = 0.5
    for _, cell in ipairs(world.cells) do cell.population, cell.agriculture, cell.craft = 10, 4, 4 end
    world.cells[2].agriculture = 1.25
    world.cells[3].craft = 1
    world.cells[4].agriculture, world.cells[4].craft = 1.25, 1
    local stats = S.Statistics(world)
    near(stats.prosperousShare, 0.25)
    near(stats.foodShortfallShare, 0.25)
    near(stats.craftShortfallShare, 0.25)
    near(stats.bothShortfallShare, 0.25)
    near(stats.prosperousShare + stats.foodShortfallShare + stats.craftShortfallShare + stats.bothShortfallShare, 1)
end)

add("跳过只登记一轮，不修改地块、保护、随机数或世代", function()
    local world = fixture(1, 1, {regionSize = 1})
    local before = {}
    for key, value in pairs(assert(world.cells[1])) do before[key] = value end
    local state, draws, protection = world.rng.state, world.rng.draws, world.protectionLeft
    check(not S.ValidateAction(world, "skip", 1, 1, true))
    check(S.ApplyAction(world, "skip", 1, 1))
    same(world.cells[1], before)
    check(world.round == 1 and world.generation == 0 and #world.history == 1)
    check(world.protectionLeft == protection and world.rng.state == state and world.rng.draws == draws)
    check(#world.actions == 1 and world.actions[1].action == "skip" and not world.actions[1].withProtection)
    local valid, reason = S.ApplyAction(world, "skip", 1, 1)
    check(not valid and reason == "round_in_progress" and #world.actions == 1)
end)

add("跳过与干预混合记录可完整重放，最后一轮与胜利边界有效", function()
    local world = S.New(20261002)
    check(S.ApplyAction(world, "skip", 1, 1))
    for _ = 1, world.config.generationsPerRound do S.Tick(world) end
    check(S.ApplyAction(world, "protect", 12, 8))
    for _ = 1, world.config.generationsPerRound do S.Tick(world) end
    check(S.ApplyAction(world, "skip", 12, 8))
    for _ = 1, world.config.generationsPerRound do S.Tick(world) end
    check(S.VerifyReplay(world))
    local last = fixture(1, 1, {regionSize = 1, rounds = 1})
    check(S.ApplyAction(last, "skip", 1, 1))
    for _ = 1, last.config.generationsPerRound do S.Tick(last) end
    local valid, reason = S.ValidateAction(last, "skip", 1, 1)
    check(not valid and reason == "generation_limit")
    local won = fixture(1, 1, {regionSize = 1})
    won.won = true
    local allowed, why = S.ValidateAction(won, "skip", 1, 1)
    check(not allowed and why == "already_won")
end)

add("推荐优先补足本地短板，忽略非法行动且不改变世界", function()
    local R = require("OriginRecommendation")
    local world = fixture(1, 1, {regionSize = 1, mobilizeAgricultureGrowth = 0, exploreAgricultureGrowth = 0, mobilizeCraftGrowth = 0, exploreCraftGrowth = 0})
    world.baselineCraft = 0.5
    check(R.Choose(world, 1, 1) == "craft")
    world.cells[1].agriculture, world.cells[1].craft = 2, 4
    local action = R.Choose(world, 1, 1)
    check(action == "agriculture" or action == "foodUp")
    local before = {}
    for key, value in pairs(assert(world.cells[1])) do before[key] = value end
    local metrics, state, draws = world.metrics, world.rng.state, world.rng.draws
    for _ = 1, 10 do check(R.Choose(world, 1, 1) == action) end
    same(world.cells[1], before)
    check(world.metrics == metrics and world.rng.state == state and world.rng.draws == draws)
    check(world.round == 0 and world.generation == 0 and #world.actions == 0)
    check(not R.Choose(world, 0, 1))
    world.protectionLeft = 0
    check(not R.Choose(world, 1, 1, true))
    check(S.ApplyAction(world, "skip", 1, 1))
    check(not R.Choose(world, 1, 1))
end)

add("实验增长参数下推荐考虑剩余轮数，不推荐已探索的制度", function()
    local R = require("OriginRecommendation")
    local world = fixture(1, 1, {regionSize = 1, mobilizeAgricultureGrowth = 0, exploreAgricultureGrowth = 0, mobilizeCraftGrowth = 0, exploreCraftGrowth = 0.015})
    world.baselineCraft = 0.5
    check(R.Choose(world, 1, 1) == "institution")
    world.round = world.config.rounds - 1
    world.generation = world.round * world.config.generationsPerRound
    check(R.Choose(world, 1, 1) == "craft")
    world.round, world.generation = 0, 0
    world.cells[1].institution = "explore"
    check(R.Choose(world, 1, 1) ~= "institution")
end)

add("里程碑边界与历史最高值保留", function()
    local P = require("OriginProgress")
    check(P.Level(0.0999) == 0 and P.Level(0.10) == 1)
    check(P.Level(0.30) == 2 and P.Level(0.60) == 3)
    check(P.Level(1.0) == 3)
    local world = fixture(1, 1)
    world.maxProsperousShare = 0.6
    world.baselineCraft = 20
    S.Tick(world)
    check(P.Level(world.maxProsperousShare) == 3 and world.prosperousStreak == 0 and not world.won)
end)

---@return OriginTestReport
function Tests.Run()
    ---@type OriginTestReport
    local report = { passed = 0, failed = 0, total = #cases, ok = false, results = {} }
    for _, case in ipairs(cases) do
        local ok, message = pcall(case.run)
        if ok then
            report.passed = report.passed + 1
            report.results[#report.results + 1] = { name = case.name, passed = true }
            print("[OriginTests] 通过 " .. case.name)
        else
            report.failed = report.failed + 1
            report.results[#report.results + 1] = { name = case.name, passed = false, error = tostring(message) }
            print("[OriginTests] 失败 " .. case.name .. "：" .. tostring(message))
        end
    end
    report.ok = report.failed == 0
    print(string.format("[OriginTests] 总计 %d，通过 %d，失败 %d", report.total, report.passed, report.failed))
    return report
end

return Tests
