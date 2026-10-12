-- 《富种起源》集中参数。纯 Lua 5.4 模块，不依赖引擎、界面或动画。
---@class OriginParameters
---@field width integer
---@field height integer
---@field rounds integer
---@field generationsPerRound integer
---@field regionSize integer
---@field defaultSeed integer
---@field protectionUses integer
---@field modelVersion string
---@field rngVersion string
---@field terrainEnabled boolean
---@field terrainPlainCapacity number
---@field terrainHillCapacity number
---@field terrainMountainCapacity number
---@field terrainPlainMigration number
---@field terrainHillMigration number
---@field terrainMountainMigration number
---@field capacityMin number
---@field capacityMax number
---@field agricultureMin number
---@field agricultureMax number
---@field craftMin number
---@field craftMax number
---@field initialFoodShareMin number
---@field initialFoodShareMax number
---@field populationNoiseMin number
---@field populationNoiseMax number
---@field explorationAreas integer
---@field explorationSize integer
---@field explorationGap integer
---@field mobilizeInstitution string
---@field exploreInstitution string
---@field naturalGrowthRate number
---@field naturalGrowthSlope number
---@field starvationPenalty number
---@field migrationResistance number
---@field migrationRate number
---@field culturalMixRate number
---@field mobilizeAgricultureGrowth number
---@field exploreAgricultureGrowth number
---@field mobilizeCraftGrowth number
---@field exploreCraftGrowth number
---@field technologyDiffusion number
---@field craftPowerWeight number
---@field mobilizePowerMultiplier number
---@field explorePowerMultiplier number
---@field replacementRate number
---@field protectionMultiplier number
---@field replacementCultureRate number
---@field prosperousFoodRatio number
---@field prosperousCraftMultiplier number
---@field victoryShare number
---@field victoryStreak integer
---@field agricultureActionMultiplier number
---@field craftActionMultiplier number
---@field mobilizeImprovementProbability number
---@field exploreImprovementProbability number
---@field foodActionStep number
---@field foodShareMin number
---@field foodShareMax number
---@field protectionDuration integer
---@field rngModulus integer
---@field rngMultiplier integer
---@field rngFallbackState integer

---@type OriginParameters
local Config = {
    width = 24,
    height = 16,
    rounds = 50,
    generationsPerRound = 5,
    regionSize = 1,
    defaultSeed = 20261002,
    protectionUses = 3,
    modelVersion = "origin-1.10.0",
    rngVersion = "park-miller-16807-v1",
    -- 地形影响软承载量与每世代迁移量。初版参数，后续按试玩调整。
    terrainEnabled = true,
    terrainPlainCapacity = 1.50,
    terrainHillCapacity = 1.00,
    terrainMountainCapacity = 0.50,
    terrainPlainMigration = 1.00,
    terrainHillMigration = 0.70,
    terrainMountainMigration = 0.40,

    capacityMin = 32.0,
    capacityMax = 48.0,
    agricultureMin = 2.8,
    agricultureMax = 3.2,
    craftMin = 1.8,
    craftMax = 2.2,
    initialFoodShareMin = 0.50,
    initialFoodShareMax = 0.65,
    populationNoiseMin = 0.90,
    populationNoiseMax = 1.10,
    -- 四个象限各抽取一个完整 2×2 区，中心留空带，保证分散且不接触。
    explorationAreas = 4,
    explorationSize = 2,
    explorationGap = 2,
    mobilizeInstitution = "mobilize",
    exploreInstitution = "explore",

    naturalGrowthRate = 0.50,
    naturalGrowthSlope = 2.0,
    starvationPenalty = 4.0,
    migrationResistance = 0.10,
    migrationRate = 0.24,
    culturalMixRate = 0.50,
    mobilizeAgricultureGrowth = 0.002,
    exploreAgricultureGrowth = 0.002,
    mobilizeCraftGrowth = 0.002,
    exploreCraftGrowth = 0.015,
    technologyDiffusion = 0.05,
    craftPowerWeight = 0.50,
    mobilizePowerMultiplier = 1.0,
    explorePowerMultiplier = 0.75,
    replacementRate = 0.20,
    protectionMultiplier = 0.25,
    replacementCultureRate = 0.20,

    prosperousFoodRatio = 1.0,
    prosperousCraftMultiplier = 2.0,
    victoryShare = 0.80,
    victoryStreak = 5,
    agricultureActionMultiplier = 1.12,
    craftActionMultiplier = 1.15,
    -- 两种主动改良共用成功率；按行动确认时的制度判定，失败也消耗一轮。
    mobilizeImprovementProbability = 0.10,
    exploreImprovementProbability = 0.30,
    foodActionStep = 0.10,
    foodShareMin = 0.25,
    foodShareMax = 0.85,
    protectionDuration = 5,

    -- 乘法最大值小于 2^53；不依赖平台整数溢出、math.random 或时间。
    rngModulus = 2147483647,
    rngMultiplier = 16807,
    rngFallbackState = 1,
}

return Config
