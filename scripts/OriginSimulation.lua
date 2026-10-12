-- 《富种起源》纯 Lua 5.4 核心。每个世界独立持有随机状态，无引擎和动画依赖。
local DefaultConfig = require("OriginConfig")
local Regions = require("OriginRegions")
local Terrain = require("OriginTerrain")
local S = {}

---@class OriginCell
---@field population number
---@field agriculture number
---@field craft number
---@field foodShare number
---@field institution string
---@field protectionTicks integer
---@field landCapacity number
---@field baseLandCapacity number
---@field terrainKind OriginTerrainKind
---@field elevation number
---@field migrationMultiplier number
---@field x integer
---@field y integer

---@class OriginMetric
---@field labor number
---@field food number
---@field craft number
---@field foodRatio number
---@field craftPerCapita number
---@field utility number
---@field power number
---@field L number
---@field F number
---@field C number
---@field s number
---@field c number
---@field U number
---@field P number

---@class OriginRandom
---@field state integer
---@field draws integer
---@field modulus integer
---@field multiplier integer

---@class OriginFlow
---@field from integer
---@field to integer
---@field amount number
---@field sourceFoodShare number
---@field utilityDifference number
---@field terrainFactor number

---@class OriginMigrationDelta
---@field incoming number
---@field outgoing number
---@field weightedIncomingF number
---@field cultureChange number
---@field populationBefore number
---@field populationAfter number
---@field foodShareBefore number
---@field foodShareAfter number

---@class OriginReplacement
---@field index integer
---@field from integer
---@field oldInstitution string
---@field newInstitution string
---@field foodShareBefore number
---@field foodShareAfter number
---@field sourceFoodShare number
---@field probability number
---@field roll number
---@field public protected boolean

---@class OriginCompetitionAttempt
---@field index integer
---@field from integer
---@field ownPower number
---@field neighborPower number
---@field probability number
---@field roll number
---@field public protected boolean
---@field success boolean

---@class OriginDelta
---@field index integer
---@field before OriginCell
---@field after OriginCell
---@field natural number
---@field naturalIncrease number
---@field naturalDecrease number
---@field incoming number
---@field outgoing number
---@field cultureChange number
---@field institutionFoodChange number
---@field foodShareChange number
---@field populationChange number
---@field agricultureChange number
---@field craftChange number
---@field agricultureLearned number
---@field craftLearned number
---@field weightedIncomingF number

---@class OriginSummary
---@field population number
---@field craftPerCapita number
---@field foodRatio number
---@field exploreShare number
---@field prosperousShare number
---@field starvingShare number
---@field foodShortfallShare number
---@field craftShortfallShare number
---@field bothShortfallShare number
---@field totalFood number
---@field totalCraft number
---@field explorePopulation number
---@field prosperousPopulation number
---@field starvingPopulation number
---@field cellCount integer
---@field generation integer
---@field round integer
---@field protectionLeft integer
---@field baselineCraft number
---@field prosperousStreak integer
---@field won boolean
---@field maxProsperousShare number

---@class OriginReport
---@field summary OriginSummary
---@field generation integer
---@field round integer
---@field initial boolean
---@field flows OriginFlow[]
---@field technologyFlows OriginTechnologyFlow[]
---@field changes OriginReplacement[]
---@field attempts OriginCompetitionAttempt[]
---@field deltas OriginDelta[]
---@field naturalIncrease number
---@field naturalDecrease number
---@field totalMigration number
---@field populationBefore number
---@field populationAfterNatural number
---@field populationAfterMigration number
---@field migrationConservationError number
---@field rngStateBefore integer
---@field rngStateAfter integer
---@field rngDrawsBefore integer
---@field rngDrawsAfter integer

---@class OriginImprovementOutcome
---@field index integer
---@field institution string
---@field probability number
---@field roll number
---@field succeeded boolean

---@class OriginActionRecord
---@field action string
---@field x integer
---@field y integer
---@field seed integer?
---@field version string?
---@field modelVersion string?
---@field rngVersion string?
---@field generation integer?
---@field round integer?
---@field rngState integer?
---@field rngDraws integer?
---@field rngStateAfter integer?
---@field rngDrawsAfter integer?
---@field improvements OriginImprovementOutcome[]?
---@field withProtection boolean?

---@class OriginTechnologyFlow
---@field from integer
---@field to integer
---@field kind string
---@field amount number
---@field relativeGain number

---@class OriginLearning
---@field agriculture number
---@field craft number

---@class OriginArea
---@field x integer
---@field y integer
---@field size integer

---@class OriginWorld
---@field config OriginParameters
---@field width integer
---@field height integer
---@field seed integer
---@field rng OriginRandom
---@field cells OriginCell[]
---@field metrics OriginMetric[]
---@field neighbors integer[][]
---@field explorationAreas OriginArea[]
---@field regions OriginRegion[]
---@field cellRegionIds integer[]
---@field geographyVersion string
---@field terrainVersion string
---@field generation integer
---@field round integer
---@field protectionLeft integer
---@field baselineCraft number
---@field history OriginReport[]
---@field actions OriginActionRecord[]
---@field prosperousStreak integer
---@field won boolean
---@field maxProsperousShare number
---@field lastReport OriginReport?

---@param value number
---@return boolean
function S.IsFinite(value)
    return type(value) == "number" and value == value and value > -math.huge and value < math.huge
end

---@param value number
---@param low number
---@param high number
---@return number
local function clamp(value, low, high)
    return math.max(low, math.min(high, value))
end

-- Lua 5.4 没有标准 math.tanh；避免 exp(2*x) 在极值时溢出。
---@param value number
---@return number
function S.Tanh(value)
    local e = math.exp(-2.0 * math.abs(value))
    local magnitude = (1.0 - e) / (1.0 + e)
    return value < 0 and -magnitude or magnitude
end

-- 配置按值复制；覆盖参数用于实验和单格阶段测试，不影响默认配置。
---@param overrides table?
---@return OriginParameters
function S.ResolveConfig(overrides)
    ---@type OriginParameters
    local config = {}
    for key, value in pairs(DefaultConfig) do config[key] = value end
    for key, value in pairs(overrides or {}) do
        assert(DefaultConfig[key] ~= nil, "未知配置参数：" .. tostring(key))
        assert(type(value) == type(DefaultConfig[key]), "配置参数类型错误：" .. key)
        config[key] = value
    end
    assert(config.modelVersion == DefaultConfig.modelVersion, "不支持的模型版本：" .. config.modelVersion)
    assert(config.rngVersion == DefaultConfig.rngVersion, "不支持的随机版本：" .. config.rngVersion)
    for key, value in pairs(config) do
        if type(value) == "number" then assert(S.IsFinite(value), "配置不是有限数：" .. key) end
    end
    for _, key in ipairs({ "width", "height", "rounds", "generationsPerRound", "regionSize",
        "victoryStreak", "protectionDuration", "rngModulus", "rngMultiplier", "rngFallbackState" }) do
        assert(config[key] >= 1 and math.tointeger(config[key]), "配置必须为正整数：" .. key)
    end
    for _, key in ipairs({ "explorationAreas", "explorationGap", "protectionUses" }) do
        assert(config[key] >= 0 and math.tointeger(config[key]), "配置必须为非负整数：" .. key)
    end
    assert(config.explorationAreas == 0 or config.explorationAreas == 4, "探索区数量只能为 0 或 4")
    assert(config.explorationSize >= 1 and math.tointeger(config.explorationSize), "探索区尺寸无效")
    assert(config.capacityMin > 0 and config.capacityMax >= config.capacityMin, "土地容量范围无效")
    for _, key in ipairs({"terrainPlainCapacity", "terrainHillCapacity", "terrainMountainCapacity"}) do
        assert(config[key] > 0, "地形承载倍率必须为正：" .. key)
    end
    for _, key in ipairs({"terrainPlainMigration", "terrainHillMigration", "terrainMountainMigration"}) do
        assert(config[key] > 0 and config[key] <= 1, "地形迁移效率必须在 (0,1] 内：" .. key)
    end
    assert(config.agricultureMin > 0 and config.agricultureMax >= config.agricultureMin, "农业范围无效")
    assert(config.craftMin > 0 and config.craftMax >= config.craftMin, "工艺范围无效")
    assert(config.initialFoodShareMin > 0 and config.initialFoodShareMax < 1
        and config.initialFoodShareMax >= config.initialFoodShareMin, "初始习惯范围无效")
    assert(config.agricultureMin * config.initialFoodShareMin > 1, "初始平衡人口必须大于零")
    assert(config.populationNoiseMin > 0 and config.populationNoiseMax >= config.populationNoiseMin, "人口扰动无效")
    assert(config.foodShareMin > 0 and config.foodShareMax < 1
        and config.foodShareMin < config.foodShareMax, "习惯边界无效")
    assert(config.foodShareMin <= config.initialFoodShareMin
        and config.foodShareMax >= config.initialFoodShareMax, "初始习惯超出边界")
    assert(config.naturalGrowthRate >= 0 and config.naturalGrowthRate < 1, "自然增长率无效")
    assert(config.naturalGrowthSlope >= 0 and config.starvationPenalty >= 0, "自然增长或效用参数无效")
    assert(config.migrationRate >= 0 and config.migrationRate < 1 and config.migrationResistance >= 0, "迁移参数无效")
    for _, key in ipairs({ "culturalMixRate", "replacementRate", "protectionMultiplier",
        "replacementCultureRate", "victoryShare", "technologyDiffusion",
        "mobilizeImprovementProbability", "exploreImprovementProbability" }) do
        assert(config[key] >= 0 and config[key] <= 1, "比例参数超出 [0,1]：" .. key)
    end
    for _, key in ipairs({ "mobilizeAgricultureGrowth", "exploreAgricultureGrowth", "mobilizeCraftGrowth", "exploreCraftGrowth", "craftPowerWeight" }) do
        assert(config[key] >= 0, "增长或权重不能为负：" .. key)
    end
    assert(config.mobilizePowerMultiplier > 0 and config.explorePowerMultiplier > 0, "实力乘数必须为正")
    assert(config.agricultureActionMultiplier > 1 and config.craftActionMultiplier > 1
        and config.foodActionStep > 0, "行动必须产生变化")
    assert(config.mobilizeInstitution ~= config.exploreInstitution, "两种制度名称必须不同")
    -- 锁定随机算法的常数，种子版本才能跨配置稳定重放。
    assert(config.rngModulus == 2147483647 and config.rngMultiplier == 16807
        and config.rngFallbackState == 1, "不可更改固定随机算法")
    return config
end

---@param seed integer
---@param config OriginParameters?
---@return OriginRandom
function S.NewRandom(seed, config)
    local cfg = config or DefaultConfig
    assert(math.tointeger(seed), "种子必须为整数")
    local state = seed % cfg.rngModulus
    if state == 0 then state = cfg.rngFallbackState end
    return { state = state, draws = 0, modulus = cfg.rngModulus, multiplier = cfg.rngMultiplier }
end

---@param rng OriginRandom
---@return number
function S.Random(rng)
    rng.state = (rng.state * rng.multiplier) % rng.modulus
    rng.draws = rng.draws + 1
    return (rng.state - 1) / (rng.modulus - 1)
end

---@param rng OriginRandom
---@param low integer
---@param high integer
---@return integer
function S.RandomInteger(rng, low, high)
    assert(low <= high, "随机整数范围为空")
    return low + math.floor(S.Random(rng) * (high - low + 1))
end

---@param cell OriginCell
---@return OriginCell
local function copyCell(cell)
    return {
        population = cell.population, agriculture = cell.agriculture, craft = cell.craft,
        foodShare = cell.foodShare, institution = cell.institution, protectionTicks = cell.protectionTicks,
        landCapacity = cell.landCapacity, x = cell.x, y = cell.y,
        baseLandCapacity = cell.baseLandCapacity, terrainKind = cell.terrainKind,
        elevation = cell.elevation, migrationMultiplier = cell.migrationMultiplier,
    }
end

---@param world OriginWorld
---@return OriginCell[]
local function snapshot(world)
    ---@type OriginCell[]
    local cells = {}
    for i, cell in ipairs(world.cells) do cells[i] = copyCell(cell) end
    return cells
end

---@param cell OriginCell
---@return boolean
function S.IsHabitable(cell)
    return cell.landCapacity > 0
end

---@param cell OriginCell
---@param config OriginParameters?
---@return OriginMetric
function S.Metrics(cell, config)
    local cfg = config or DefaultConfig
    assert(S.IsFinite(cell.population) and cell.population > 0, "人口必须是有限正数")
    assert(S.IsFinite(cell.landCapacity) and cell.landCapacity > 0, "土地容量必须是有限正数")
    assert(S.IsFinite(cell.agriculture) and cell.agriculture > 0
        and S.IsFinite(cell.craft) and cell.craft > 0, "技术必须是有限正数")
    assert(S.IsFinite(cell.foodShare) and cell.foodShare >= 0 and cell.foodShare <= 1, "习惯必须在 [0,1]")
    assert(cell.institution == cfg.exploreInstitution or cell.institution == cfg.mobilizeInstitution, "未知制度")
    local n, k, f = cell.population, cell.landCapacity, cell.foodShare
    -- 先计算人均劳动，避免极小人口下 F/N 的精度损失；与给定公式代数等价。
    local laborPerCapita = 1.0 / (1.0 + n / k)
    local labor = n * laborPerCapita
    local foodRatio = cell.agriculture * f * laborPerCapita
    local craftPerCapita = cell.craft * (1.0 - f) * laborPerCapita
    local food, craft = n * foodRatio, n * craftPerCapita
    local utility = math.log(1.0 + craftPerCapita) - cfg.starvationPenalty * math.max(0, 1.0 - foodRatio)
    local multiplier = cell.institution == cfg.exploreInstitution
        and cfg.explorePowerMultiplier or cfg.mobilizePowerMultiplier
    local power = multiplier * (food + cfg.craftPowerWeight * craft)
    return {
        labor = labor, food = food, craft = craft, foodRatio = foodRatio,
        craftPerCapita = craftPerCapita, utility = utility, power = power,
        L = labor, F = food, C = craft, s = foodRatio, c = craftPerCapita, U = utility, P = power,
    }
end

---@param world OriginWorld
---@return OriginMetric[]
function S.RefreshMetrics(world)
    ---@type OriginMetric[]
    local metrics = {}
    for i, cell in ipairs(world.cells) do metrics[i] = S.Metrics(cell, world.config) end
    world.metrics = metrics
    return metrics
end

-- 行优先索引、四邻域、固定边界；没有跨边界邻居和对角线。
---@param width integer
---@param height integer
---@return integer[][]
function S.BuildNeighbors(width, height)
    ---@type integer[][]
    local neighbors = {}
    for y = 1, height do
        for x = 1, width do
            local i = (y - 1) * width + x
            ---@type integer[]
            local adjacent = {}
            if x > 1 then adjacent[#adjacent + 1] = i - 1 end
            if x < width then adjacent[#adjacent + 1] = i + 1 end
            if y > 1 then adjacent[#adjacent + 1] = i - width end
            if y < height then adjacent[#adjacent + 1] = i + width end
            neighbors[i] = adjacent
        end
    end
    return neighbors
end

---@param world OriginWorld
---@return number
local function totalPopulation(world)
    local population = 0.0
    for _, cell in ipairs(world.cells) do population = population + cell.population end
    return population
end

---@param world OriginWorld
---@return OriginSummary
function S.Statistics(world)
    -- 不信任可能因 UI/实验修改而过期的缓存；统计始终读取当前格子。
    local population, food, craft = 0.0, 0.0, 0.0
    local explore, prosperous, starving = 0.0, 0.0, 0.0
    local foodShortfall, craftShortfall, bothShortfall = 0.0, 0.0, 0.0
    local cfg = world.config
    for _, cell in ipairs(world.cells) do
        local m = S.Metrics(cell, cfg)
        population = population + cell.population
        food, craft = food + m.food, craft + m.craft
        if cell.institution == cfg.exploreInstitution then explore = explore + cell.population end
        local fed = m.foodRatio >= cfg.prosperousFoodRatio
        local equipped = m.craftPerCapita >= cfg.prosperousCraftMultiplier * world.baselineCraft
        if fed and equipped then
            prosperous = prosperous + cell.population
        elseif equipped then foodShortfall = foodShortfall + cell.population
        elseif fed then craftShortfall = craftShortfall + cell.population
        else bothShortfall = bothShortfall + cell.population
        end
        if m.foodRatio < 1.0 then starving = starving + cell.population end
    end
    assert(population > 0, "世界必须保留可居住土地与人口")
    return {
        population = population, craftPerCapita = craft / population, foodRatio = food / population,
        exploreShare = explore / population, prosperousShare = prosperous / population,
        starvingShare = starving / population, totalFood = food, totalCraft = craft,
        foodShortfallShare = foodShortfall / population, craftShortfallShare = craftShortfall / population,
        bothShortfallShare = bothShortfall / population,
        explorePopulation = explore, prosperousPopulation = prosperous, starvingPopulation = starving,
        cellCount = #world.cells, generation = world.generation, round = world.round,
        protectionLeft = world.protectionLeft, baselineCraft = world.baselineCraft,
        prosperousStreak = world.prosperousStreak, won = world.won, maxProsperousShare = world.maxProsperousShare,
    }
end

---@param world OriginWorld
local function seedExploration(world)
    local cfg = world.config
    if cfg.explorationAreas == 0 then return end
    local size, gap = cfg.explorationSize, cfg.explorationGap
    local leftEnd = (cfg.width - gap) // 2
    local topEnd = (cfg.height - gap) // 2
    local rightStart, bottomStart = leftEnd + gap + 1, topEnd + gap + 1
    assert(leftEnd >= size and topEnd >= size
        and cfg.width - rightStart + 1 >= size and cfg.height - bottomStart + 1 >= size,
        "地图太小，无法容纳四个分散探索区；单格测试请设置 explorationAreas=0")
    for row = 1, 2 do
        for column = 1, 2 do
            local xMin = column == 1 and 1 or rightStart
            local xMax = column == 1 and leftEnd - size + 1 or cfg.width - size + 1
            local yMin = row == 1 and 1 or bottomStart
            local yMax = row == 1 and topEnd - size + 1 or cfg.height - size + 1
            local x = S.RandomInteger(world.rng, xMin, xMax)
            local y = S.RandomInteger(world.rng, yMin, yMax)
            world.explorationAreas[#world.explorationAreas + 1] = { x = x, y = y, size = size }
            for cy = y, y + size - 1 do
                for cx = x, x + size - 1 do
                    world.cells[(cy - 1) * cfg.width + cx].institution = cfg.exploreInstitution
                end
            end
        end
    end
end

---@param seed number?
---@param config table?
---@return OriginWorld
function S.New(seed, config)
    local cfg = S.ResolveConfig(config)
    local initialSeed = assert(math.tointeger(seed or cfg.defaultSeed), "种子必须为整数")
    -- 地区轮廓使用独立随机流；每格仍固定消耗原来的五次模拟随机抽样。
    local geography = Regions.Generate(initialSeed, cfg)
    local terrain = Terrain.Generate(initialSeed, cfg)
    ---@type OriginWorld
    local world = {
        config = cfg, width = cfg.width, height = cfg.height, seed = initialSeed,
        rng = S.NewRandom(initialSeed, cfg), cells = {}, metrics = {},
        neighbors = S.BuildNeighbors(cfg.width, cfg.height), explorationAreas = {},
        regions = geography.regions, cellRegionIds = geography.cellRegionIds,
        geographyVersion = geography.version,
        terrainVersion = terrain.version,
        generation = 0, round = 0, protectionLeft = cfg.protectionUses, baselineCraft = 0.0,
        history = {}, actions = {}, prosperousStreak = 0, won = false, maxProsperousShare = 0.0,
    }
    for y = 1, cfg.height do
        for x = 1, cfg.width do
            local regionId = assert(world.cellRegionIds[(y - 1) * cfg.width + x])
            local region = assert(world.regions[regionId])
            local values = Regions.InitialValues(region, {
                S.Random(world.rng), S.Random(world.rng), S.Random(world.rng),
                S.Random(world.rng), S.Random(world.rng),
            }, cfg)
            local tile = terrain.cells[(y - 1) * cfg.width + x]
            local profile = Terrain.Profile(tile.kind, cfg)
            local k, a, b, f = values.k * profile.capacityMultiplier, values.a, values.b, values.f
            local n = k * (a * f - 1.0) * values.noise
            world.cells[#world.cells + 1] = {
                population = n, agriculture = a, craft = b, foodShare = f,
                institution = cfg.mobilizeInstitution, protectionTicks = 0, landCapacity = k, x = x, y = y,
                baseLandCapacity = values.k, terrainKind = tile.kind, elevation = tile.elevation,
                migrationMultiplier = profile.migrationMultiplier,
            }
        end
    end
    seedExploration(world)
    S.RefreshMetrics(world)
    -- c0 仅在开局赋值一次，之后不随行动、移民或技术改变。
    world.baselineCraft = S.Statistics(world).craftPerCapita
    local summary = S.Statistics(world)
    world.maxProsperousShare = summary.prosperousShare
    summary.maxProsperousShare = world.maxProsperousShare
    ---@type OriginReport
    local initial = {
        summary = summary, generation = 0, round = 0, initial = true,
        flows = {}, technologyFlows = {}, changes = {}, attempts = {}, deltas = {}, naturalIncrease = 0.0, naturalDecrease = 0.0,
        totalMigration = 0.0, populationBefore = summary.population,
        populationAfterNatural = summary.population, populationAfterMigration = summary.population,
        migrationConservationError = 0.0, rngStateBefore = world.rng.state, rngStateAfter = world.rng.state,
        rngDrawsBefore = world.rng.draws, rngDrawsAfter = world.rng.draws,
    }
    world.history[1], world.lastReport = initial, initial
    return world
end

---@param world OriginWorld
---@param action string
---@param x number
---@param y number
---@param withProtection boolean?
---@return boolean, string
function S.ValidateAction(world, action, x, y, withProtection)
    local cfg = world.config
    if action ~= "agriculture" and action ~= "craft" and action ~= "foodUp"
        and action ~= "foodDown" and action ~= "institution" and action ~= "protect" and action ~= "skip" then
        return false, "unknown_action"
    end
    -- 旧记录可传 false/nil；禁止旧调用把保护附加到其他行动。
    if withProtection ~= nil and withProtection ~= false then return false, "invalid_protection" end
    if type(x) ~= "number" or type(y) ~= "number" or not math.tointeger(x) or not math.tointeger(y)
        or x < 1 or y < 1 or x + cfg.regionSize - 1 > cfg.width or y + cfg.regionSize - 1 > cfg.height then
        return false, "region_out_of_bounds"
    end
    if world.won then return false, "already_won" end
    if world.generation >= cfg.rounds * cfg.generationsPerRound then return false, "generation_limit" end
    if world.round >= cfg.rounds then return false, "round_limit" end
    if world.generation < world.round * cfg.generationsPerRound then return false, "round_in_progress" end
    if action == "skip" then
        return true, "ok"
    end
    if action == "protect" and world.protectionLeft <= 0 then return false, "no_protection_uses" end
    local changed, habitable = false, 0
    for cy = y, y + cfg.regionSize - 1 do
        for cx = x, x + cfg.regionSize - 1 do
            local cell = world.cells[(cy - 1) * cfg.width + cx]
            if S.IsHabitable(cell) then
                habitable = habitable + 1
                if action == "agriculture" then
                    local nextValue = cell.agriculture * cfg.agricultureActionMultiplier
                    if not S.IsFinite(nextValue) then return false, "non_finite_result" end
                    changed = changed or nextValue ~= cell.agriculture
                elseif action == "craft" then
                    local nextValue = cell.craft * cfg.craftActionMultiplier
                    if not S.IsFinite(nextValue) then return false, "non_finite_result" end
                    changed = changed or nextValue ~= cell.craft
                elseif action == "foodUp" then
                    changed = changed or clamp(cell.foodShare + cfg.foodActionStep, cfg.foodShareMin, cfg.foodShareMax) ~= cell.foodShare
                elseif action == "foodDown" then
                    changed = changed or clamp(cell.foodShare - cfg.foodActionStep, cfg.foodShareMin, cfg.foodShareMax) ~= cell.foodShare
                elseif action == "institution" then
                    changed = changed or cell.institution ~= cfg.exploreInstitution
                elseif action == "protect" then
                    changed = changed or cell.protectionTicks < cfg.protectionDuration
                end
            end
        end
    end
    if habitable == 0 then return false, "no_habitable_cells" end
    if not changed then return false, "no_change" end
    return true, "ok"
end

---@param cell OriginCell
---@param config OriginParameters
---@return number
function S.ImprovementProbability(cell, config)
    return cell.institution == config.exploreInstitution and config.exploreImprovementProbability
        or config.mobilizeImprovementProbability
end

-- 仅登记行动与修改区域；改良失败也占用回合。绝不自动 Tick；round 只在此处递增。
---@param world OriginWorld
---@param action string
---@param x number
---@param y number
---@param withProtection boolean?
---@return boolean, string
function S.ApplyAction(world, action, x, y, withProtection)
    local valid, reason = S.ValidateAction(world, action, x, y, withProtection)
    if not valid then return false, reason end
    local regionX, regionY = assert(math.tointeger(x)), assert(math.tointeger(y))
    local cfg = world.config
    local rngState, rngDraws = world.rng.state, world.rng.draws
    ---@type OriginImprovementOutcome[]
    local improvements = {}
    for cy = regionY, regionY + cfg.regionSize - 1 do
        for cx = regionX, regionX + cfg.regionSize - 1 do
            local cell = world.cells[(cy - 1) * cfg.width + cx]
            if action ~= "skip" and S.IsHabitable(cell) then
                if action == "agriculture" or action == "craft" then
                    -- 验证通过后才抽签；固定逐格顺序，边界概率 0/1 也消耗一次随机数。
                    local probability = S.ImprovementProbability(cell, cfg)
                    local roll = S.Random(world.rng)
                    local succeeded = roll < probability
                    improvements[#improvements + 1] = {index = (cy - 1) * cfg.width + cx,
                        institution = cell.institution, probability = probability, roll = roll, succeeded = succeeded}
                    if succeeded then
                        if action == "agriculture" then cell.agriculture = cell.agriculture * cfg.agricultureActionMultiplier
                        else cell.craft = cell.craft * cfg.craftActionMultiplier end
                    end
                elseif action == "foodUp" then cell.foodShare = clamp(cell.foodShare + cfg.foodActionStep, cfg.foodShareMin, cfg.foodShareMax)
                elseif action == "foodDown" then cell.foodShare = clamp(cell.foodShare - cfg.foodActionStep, cfg.foodShareMin, cfg.foodShareMax)
                elseif action == "institution" then cell.institution = cfg.exploreInstitution
                elseif action == "protect" then cell.protectionTicks = math.max(cell.protectionTicks, cfg.protectionDuration)
                end
            end
        end
    end
    if action == "protect" then world.protectionLeft = world.protectionLeft - 1 end
    world.round = world.round + 1
    world.actions[#world.actions + 1] = {
        action = action, x = regionX, y = regionY, seed = world.seed, version = cfg.modelVersion,
        modelVersion = cfg.modelVersion, rngVersion = cfg.rngVersion,
        generation = world.generation, round = world.round, rngState = rngState, rngDraws = rngDraws,
        rngStateAfter = world.rng.state, rngDrawsAfter = world.rng.draws, improvements = improvements,
        withProtection = false,
    }
    S.RefreshMetrics(world)
    return true, "ok"
end

-- 模拟和设置曲线共用同一函数；返回每世代人口净变化比例。
---@param foodRatio number
---@param cfg OriginParameters
---@return number
function S.PopulationChangeRate(foodRatio, cfg)
    return S.PopulationChange(1, foodRatio, cfg)
end

---@param population number
---@param foodRatio number
---@param cfg OriginParameters
---@return number
function S.PopulationChange(population, foodRatio, cfg)
    return population * cfg.naturalGrowthRate * S.Tanh(cfg.naturalGrowthSlope * (foodRatio - 1.0))
end

-- 以下阶段函数显式暴露用于公式测试；直接调用不会推进世代或写入历史。
---@param world OriginWorld
---@return number[]
function S.NaturalGrowth(world)
    local metrics = S.RefreshMetrics(world)
    ---@type number[]
    local changes = {}
    local cfg = world.config
    for i, cell in ipairs(world.cells) do
        local change = S.PopulationChange(cell.population, metrics[i].foodRatio, cfg)
        changes[i] = change
        cell.population = cell.population + change
    end
    S.RefreshMetrics(world)
    return changes
end

-- 同步迁移设计：
--   i -- Mij --> j  （仅四邻域，所有 M 来自同一个迁移前快照）
--   N'i = Ni - ΣMij + ΣMji，来者本世代不能再次外迁。
--   每个来源 O < Ni*migrationRate，D=0 不除零；单格没有邻居自然无流。
---@param world OriginWorld
---@return OriginFlow[], OriginMigrationDelta[]
function S.Migrate(world)
    local cfg = world.config
    local metrics, before = S.RefreshMetrics(world), snapshot(world)
    ---@type OriginFlow[]
    local flows = {}
    ---@type OriginMigrationDelta[]
    local deltas = {}
    ---@type number[]
    local incomingWeighted = {}
    for i, cell in ipairs(before) do
        deltas[i] = {
            incoming = 0.0, outgoing = 0.0, weightedIncomingF = cell.foodShare, cultureChange = 0.0,
            populationBefore = cell.population, populationAfter = cell.population,
            foodShareBefore = cell.foodShare, foodShareAfter = cell.foodShare,
        }
        incomingWeighted[i] = 0.0
    end
    for i, cell in ipairs(before) do
        ---@type number[]
        local differences = {}
        local totalDifference = 0.0
        local adjacent = world.neighbors[i] or {}
        for a, j in ipairs(adjacent) do
            local difference = math.max(0.0, metrics[j].utility - metrics[i].utility - cfg.migrationResistance)
            differences[a] = difference
            totalDifference = totalDifference + difference
        end
        if totalDifference > 0 then
            local outgoing = cell.population * cfg.migrationRate * totalDifference / (1.0 + totalDifference)
            for a, j in ipairs(adjacent) do
                local difference = differences[a] or 0.0
                if difference > 0 then
                    -- 地形减慢这条边的实际迁移量；未能迁出的人留在来源，不转分给其他边。
                    local terrainFactor = math.min(cell.migrationMultiplier, before[j].migrationMultiplier)
                    local amount = outgoing * difference / totalDifference * terrainFactor
                    ---@type OriginFlow
                    local flow = {
                        from = i, to = j, amount = amount, sourceFoodShare = cell.foodShare,
                        utilityDifference = difference,
                        terrainFactor = terrainFactor,
                    }
                    flows[#flows + 1] = flow
                    deltas[i].outgoing = deltas[i].outgoing + amount
                    deltas[j].incoming = deltas[j].incoming + amount
                    incomingWeighted[j] = incomingWeighted[j] + amount * cell.foodShare
                end
            end
        end
    end
    for i, cell in ipairs(world.cells) do
        local delta = deltas[i]
        local population = before[i].population - delta.outgoing + delta.incoming
        local f = before[i].foodShare
        local average = delta.incoming > 0 and incomingWeighted[i] / delta.incoming or f
        local nextF = f
        if S.IsHabitable(cell) then nextF = f + cfg.culturalMixRate * (delta.incoming / population) * (average - f) end
        cell.population, cell.foodShare = population, nextF
        delta.populationAfter, delta.foodShareAfter = population, nextF
        delta.weightedIncomingF, delta.cultureChange = average, nextF - f
    end
    S.RefreshMetrics(world)
    return flows, deltas
end

---@param world OriginWorld
---@return OriginLearning[], OriginTechnologyFlow[]
function S.GrowTechnology(world)
    local cfg = world.config
    for _, cell in ipairs(world.cells) do
        if S.IsHabitable(cell) then
            local rate = cell.institution == cfg.exploreInstitution and cfg.exploreCraftGrowth or cfg.mobilizeCraftGrowth
            local agricultureRate = cell.institution == cfg.exploreInstitution and cfg.exploreAgricultureGrowth or cfg.mobilizeAgricultureGrowth
            cell.agriculture = cell.agriculture * (1.0 + agricultureRate)
            cell.craft = cell.craft * (1.0 + rate)
        end
    end
    -- 先读取所有格子的自然增长后技术，再同步学习；同世代不会跨两格传播。
    ---@type OriginLearning[]
    local learned = {}
    ---@type OriginTechnologyFlow[]
    local flows = {}
    for i, cell in ipairs(world.cells) do
        local maxA, maxB, fromA, fromB = cell.agriculture, cell.craft, i, i
        for _, j in ipairs(assert(world.neighbors[i], "地块缺少邻接表")) do
            local neighbor = world.cells[j]
            if neighbor.agriculture > maxA then maxA, fromA = neighbor.agriculture, j end
            if neighbor.craft > maxB then maxB, fromB = neighbor.craft, j end
        end
        local a = cfg.technologyDiffusion * (maxA - cell.agriculture)
        local b = cfg.technologyDiffusion * (maxB - cell.craft)
        learned[i] = { agriculture = a, craft = b }
        if a > 0 then flows[#flows + 1] = { from = fromA, to = i, kind = "agriculture", amount = a, relativeGain = a / cell.agriculture } end
        if b > 0 then flows[#flows + 1] = { from = fromB, to = i, kind = "craft", amount = b, relativeGain = b / cell.craft } end
    end
    for i, cell in ipairs(world.cells) do
        cell.agriculture = cell.agriculture + learned[i].agriculture
        cell.craft = cell.craft + learned[i].craft
    end
    S.RefreshMetrics(world)
    return learned, flows
end

---@param ownPower number
---@param neighborPower number
---@param protected boolean
---@param cfg OriginParameters
---@return number
local function replacementProbability(ownPower, neighborPower, protected, cfg)
    if neighborPower <= ownPower then return 0 end
    local probability = cfg.replacementRate * (neighborPower - ownPower) / (neighborPower + ownPower)
    return protected and probability * cfg.protectionMultiplier or probability
end

-- 当前状态下单次竞争的无条件概率；并列最强邻居均匀抽取，不消耗随机数。
---@param world OriginWorld
---@param index integer
---@return number
function S.InstitutionChangeProbability(world, index)
    local cell = world.cells[index]
    local ownPower = S.Metrics(cell, world.config).power
    local highest, count, foreignCount = -math.huge, 0, 0
    for _, j in ipairs(world.neighbors[index] or {}) do
        local neighbor = world.cells[j]
        local power = S.Metrics(neighbor, world.config).power
        if power > highest then
            highest, count, foreignCount = power, 1, neighbor.institution ~= cell.institution and 1 or 0
        elseif power == highest then
            count = count + 1
            if neighbor.institution ~= cell.institution then foreignCount = foreignCount + 1 end
        end
    end
    if count == 0 or foreignCount == 0 then return 0 end
    return replacementProbability(ownPower, highest, cell.protectionTicks > 0, world.config) * foreignCount / count
end

-- 先选所有候选并抽签，最后统一替代；不传播同世代刚替代的制度和习惯。
---@param world OriginWorld
---@return OriginReplacement[], OriginCompetitionAttempt[]
function S.Compete(world)
    local cfg = world.config
    local metrics, before = S.RefreshMetrics(world), snapshot(world)
    ---@type OriginReplacement[]
    local changes = {}
    ---@type OriginCompetitionAttempt[]
    local attempts = {}
    for i, cell in ipairs(before) do
        local highest = -math.huge
        ---@type integer[]
        local candidates = {}
        local adjacent = world.neighbors[i] or {}
        for _, j in ipairs(adjacent) do
            local power = metrics[j].power
            if power > highest then highest, candidates = power, { j }
            elseif power == highest then candidates[#candidates + 1] = j end
        end
        if #candidates > 0 then
            local selected = #candidates > 1 and S.RandomInteger(world.rng, 1, #candidates) or 1
            -- 数组非空，且随机索引严格位于 [1,#candidates]。
            local j = candidates[selected] --[[@as integer]]
            local source = before[j] --[[@as OriginCell]]
            if highest > metrics[i].power and source.institution ~= cell.institution then
                local protected = cell.protectionTicks > 0
                local probability = replacementProbability(metrics[i].power, highest, protected, cfg)
                local roll = S.Random(world.rng)
                local success = roll < probability
                attempts[#attempts + 1] = {
                    index = i, from = j, ownPower = metrics[i].power, neighborPower = highest,
                    probability = probability, roll = roll, protected = protected, success = success,
                }
                if success then
                    changes[#changes + 1] = {
                        index = i, from = j, oldInstitution = cell.institution, newInstitution = source.institution,
                        foodShareBefore = cell.foodShare,
                        foodShareAfter = (1.0 - cfg.replacementCultureRate) * cell.foodShare
                            + cfg.replacementCultureRate * source.foodShare,
                        sourceFoodShare = source.foodShare, probability = probability, roll = roll, protected = protected,
                    }
                end
            end
        end
    end
    for _, change in ipairs(changes) do
        local cell = world.cells[change.index]
        cell.institution, cell.foodShare = change.newInstitution, change.foodShareAfter
    end
    S.RefreshMetrics(world)
    return changes, attempts
end

---@param world OriginWorld
function S.DecayProtection(world)
    for _, cell in ipairs(world.cells) do cell.protectionTicks = math.max(0, cell.protectionTicks - 1) end
end

---@param world OriginWorld
---@return OriginReport
function S.Tick(world)
    assert(world.generation < world.config.rounds * world.config.generationsPerRound, "已到达世代上限")
    -- 允许 baseline 在胜利后继续到上限；交互和 Replay 由调用者在 won 时停止。
    local before = snapshot(world)
    local rngState, rngDraws = world.rng.state, world.rng.draws
    local populationBefore = totalPopulation(world)
    local natural = S.NaturalGrowth(world)
    local afterNatural = totalPopulation(world)
    local flows, migration = S.Migrate(world)
    local afterMigration = totalPopulation(world)
    local learning, technologyFlows = S.GrowTechnology(world)
    local changes, attempts = S.Compete(world)
    S.DecayProtection(world)
    world.generation = world.generation + 1
    ---@type OriginDelta[]
    local deltas = {}
    ---@type table<number, number>
    local institutionFoodChanges = {}
    for _, change in ipairs(changes) do
        institutionFoodChanges[change.index] = change.foodShareAfter - change.foodShareBefore
    end
    local naturalIncrease, naturalDecrease, totalMigration = 0.0, 0.0, 0.0
    for i, cell in ipairs(world.cells) do
        local delta = migration[i] --[[@as OriginMigrationDelta]]
        local previous = before[i] --[[@as OriginCell]]
        local naturalChange = natural[i] or 0.0
        local increase, decrease = math.max(0.0, naturalChange), math.max(0.0, -naturalChange)
        naturalIncrease, naturalDecrease = naturalIncrease + increase, naturalDecrease + decrease
        totalMigration = totalMigration + delta.outgoing
        ---@type OriginDelta
        local cellDelta = {
            index = i, before = previous, after = copyCell(cell), natural = naturalChange,
            naturalIncrease = increase, naturalDecrease = decrease, incoming = delta.incoming, outgoing = delta.outgoing,
            cultureChange = delta.cultureChange, institutionFoodChange = institutionFoodChanges[i] or 0.0,
            foodShareChange = cell.foodShare - previous.foodShare, populationChange = cell.population - previous.population,
            agricultureChange = cell.agriculture - previous.agriculture, craftChange = cell.craft - previous.craft,
            agricultureLearned = learning[i].agriculture, craftLearned = learning[i].craft,
            weightedIncomingF = delta.weightedIncomingF,
        }
        deltas[i] = cellDelta
    end
    local summary = S.Statistics(world)
    if summary.prosperousShare >= world.config.victoryShare then
        world.prosperousStreak = world.prosperousStreak + 1
    else world.prosperousStreak = 0 end
    world.won = world.won or world.prosperousStreak >= world.config.victoryStreak
    world.maxProsperousShare = math.max(world.maxProsperousShare, summary.prosperousShare)
    summary.prosperousStreak, summary.won = world.prosperousStreak, world.won
    summary.maxProsperousShare = world.maxProsperousShare
    ---@type OriginReport
    local report = {
        summary = summary, generation = world.generation, round = world.round, initial = false,
        flows = flows, technologyFlows = technologyFlows, changes = changes, attempts = attempts, deltas = deltas,
        naturalIncrease = naturalIncrease, naturalDecrease = naturalDecrease, totalMigration = totalMigration,
        populationBefore = populationBefore, populationAfterNatural = afterNatural, populationAfterMigration = afterMigration,
        migrationConservationError = afterMigration - afterNatural,
        rngStateBefore = rngState, rngStateAfter = world.rng.state,
        rngDrawsBefore = rngDraws, rngDrawsAfter = world.rng.draws,
    }
    world.history[#world.history + 1], world.lastReport = report, report
    return report
end

-- 返回初始点及全部世代统计，共 1+rounds*generationsPerRound 点。
---@param seed number?
---@param config table?
---@return OriginSummary[]
function S.Baseline(seed, config)
    local world = S.New(seed, config)
    ---@type OriginSummary[]
    local summaries = { assert(world.history[1]).summary }
    for i = 1, world.config.rounds * world.config.generationsPerRound do summaries[i + 1] = S.Tick(world).summary end
    return summaries
end

---@param left any
---@param right any
---@return boolean
local function equal(left, right)
    if type(left) ~= type(right) then return false end
    if type(left) ~= "table" then return left == right end
    for key, value in pairs(left) do if not equal(value, right[key]) then return false end end
    for key in pairs(right) do if left[key] == nil then return false end end
    return true
end

-- 接受 ApplyAction 产生的完整记录或 {action,x,y} 简单记录。
-- 完整记录的世代、回合、种子、版本与随机状态逐项验证；保护作为独立行动重放。
---@param seed number?
---@param actions OriginActionRecord[]
---@param config table?
---@return OriginWorld
function S.Replay(seed, actions, config)
    local world = S.New(seed, config)
    for i, record in ipairs(actions) do
        assert(not world.won, "胜利后不能继续重放行动：" .. i)
        assert(record.seed == nil or record.seed == world.seed, "重放种子不匹配")
        assert(record.version == nil or record.version == world.config.modelVersion, "重放版本不匹配")
        assert(record.modelVersion == nil or record.modelVersion == world.config.modelVersion, "重放模型版本不匹配")
        assert(record.rngVersion == nil or record.rngVersion == world.config.rngVersion, "重放随机版本不匹配")
        assert(record.generation == nil or record.generation == world.generation, "重放行动世代不匹配")
        assert(record.round == nil or record.round == world.round + 1, "重放行动回合不匹配")
        assert(record.rngState == nil or record.rngState == world.rng.state, "重放随机状态不匹配")
        assert(record.rngDraws == nil or record.rngDraws == world.rng.draws, "重放随机调用数不匹配")
        local valid, reason = S.ApplyAction(world, record.action, record.x, record.y, record.withProtection)
        assert(valid, "重放行动无效：" .. i .. " / " .. reason)
        assert(record.rngStateAfter == nil or record.rngStateAfter == world.rng.state, "重放行动后随机状态不匹配")
        assert(record.rngDrawsAfter == nil or record.rngDrawsAfter == world.rng.draws, "重放行动后随机调用数不匹配")
        assert(record.improvements == nil or equal(record.improvements, world.actions[i].improvements), "重放改良结果不匹配")
        for _ = 1, world.config.generationsPerRound do
            if world.won then break end
            S.Tick(world)
        end
    end
    return world
end

-- 按值比较完整模型记录；不使用序列化、pairs 顺序或容忍差异掩盖重放问题。
---@param world OriginWorld
---@return boolean, string
function S.VerifyReplay(world)
    local ok, replayed = pcall(S.Replay, world.seed, world.actions, world.config)
    if not ok then return false, tostring(replayed) end
    if world.geographyVersion ~= replayed.geographyVersion
        or not equal(world.regions, replayed.regions)
        or not equal(world.cellRegionIds, replayed.cellRegionIds) then return false, "geography_mismatch" end
    if world.terrainVersion ~= replayed.terrainVersion then return false, "terrain_mismatch" end
    if not equal(world.cells, replayed.cells) then return false, "cells_mismatch" end
    if not equal(world.history, replayed.history) then return false, "history_mismatch" end
    if not equal(world.actions, replayed.actions) then return false, "actions_mismatch" end
    if not equal(world.rng, replayed.rng) then return false, "rng_mismatch" end
    if not equal(S.Statistics(world), S.Statistics(replayed)) then return false, "summary_mismatch" end
    return true, "ok"
end

return S
