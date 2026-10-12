-- 地形生成与参数契约测试；require 不执行，显式调用 Tests.Run()。
local Terrain = require("OriginTerrain")
local Config = require("OriginConfig")
local Tests = {}

---@class OriginTerrainTestCase
---@field name string
---@field run fun()

---@type OriginTerrainTestCase[]
local cases = {}

---@param name string
---@param run fun()
local function add(name, run)
    cases[#cases + 1] = { name = name, run = run }
end

---@param overrides table?
---@return OriginParameters
local function configWith(overrides)
    local config = {} --[[@as OriginParameters]]
    for key, value in pairs(Config) do config[key] = value end
    for key, value in pairs(overrides or {}) do config[key] = value end
    return config
end

-- 极小地图不强制出现丘陵或山地。
local LandConfig = configWith()

---@param actual any
---@param expected any
local function same(actual, expected)
    assert(type(actual) == type(expected), "重放类型不同")
    if type(actual) ~= "table" then assert(actual == expected, "重放数值不同") return end
    for key, value in pairs(actual) do same(value, expected[key]) end
    for key in pairs(expected) do assert(actual[key] ~= nil, "重放缺少字段") end
end

---@param map OriginTerrainMap
---@return string
local function kindSignature(map)
    local parts = {}
    for _, cell in ipairs(map.cells) do parts[#parts + 1] = cell.kind end
    return table.concat(parts, ",")
end

---@class OriginTerrainConstraintRange
---@field checkedMaps integer
---@field minPlainShare number
---@field maxPlainShare number
---@field minMountainShare number
---@field maxMountainShare number

---@return OriginTerrainConstraintRange
local function newConstraintRange()
    return {checkedMaps = 0, minPlainShare = 1, maxPlainShare = 0,
        minMountainShare = 1, maxMountainShare = 0}
end

-- 由同一遍约束验证累积证据，不另生成地图或重复采样；Run 开始时重置。
local constraints = {allMaps = newConstraintRange(), defaultSizeEnabled = newConstraintRange()}

---@param range OriginTerrainConstraintRange
---@param count integer
---@param counts table<string, integer>
local function recordConstraints(range, count, counts)
    range.checkedMaps = range.checkedMaps + 1
    range.minPlainShare = math.min(range.minPlainShare, counts.plain / count)
    range.maxPlainShare = math.max(range.maxPlainShare, counts.plain / count)
    range.minMountainShare = math.min(range.minMountainShare, counts.mountain / count)
    range.maxMountainShare = math.max(range.maxMountainShare, counts.mountain / count)
end

---@param map OriginTerrainMap
---@param config OriginParameters
local function validateMap(map, config)
    assert(map.version == "origin-terrain-5", "缺少地形算法版本")
    assert(#map.cells == config.width * config.height, "地形没有覆盖全图")
    local counts = { plain = 0, hill = 0, mountain = 0 }
    for _, cell in ipairs(map.cells) do
        assert(counts[cell.kind], "未知地形")
        counts[cell.kind] = counts[cell.kind] + 1
        assert(cell.elevation == cell.elevation and cell.elevation >= 0 and cell.elevation <= 1, "高度须有限且在 [0,1]")
    end
    -- 分母始终是全图格数，用整数不等式区分“低于”与“不超过”。
    local count = config.width * config.height
    assert(5 * counts.plain > 3 * count, "最终平原比例必须严格超过60%")
    assert(20 * counts.mountain < 3 * count, "最终山地比例必须严格低于15%")
    assert(counts.plain + counts.hill + counts.mountain == count, "地形计数未覆盖全图")
    recordConstraints(constraints.allMaps, count, counts)
    if config.width == Config.width and config.height == Config.height
        and config.terrainEnabled then
        recordConstraints(constraints.defaultSizeEnabled, count, counts)
    end
end

add("同种子可精确重放地形", function()
    for _, seed in ipairs({ Config.defaultSeed, 0, 1, -317, 2147483647 }) do
        same(Terrain.Generate(seed, LandConfig), Terrain.Generate(seed, LandConfig))
    end
end)

add("不同种子改变三类地形布局", function()
    local first = kindSignature(Terrain.Generate(Config.defaultSeed, LandConfig))
    local changed = 0
    for offset = 1, 8 do
        if kindSignature(Terrain.Generate(Config.defaultSeed + offset, LandConfig)) ~= first then changed = changed + 1 end
    end
    assert(changed >= 6, "不同种子的地形没有充分变化")
end)

add("多种子三类地形完整覆盖且空间成片", function()
    for seed = 1, 64 do
        local map = Terrain.Generate(seed * 7919, LandConfig)
        validateMap(map, LandConfig)
        local sameEdges, edges, isolated = 0, 0, 0
        for y = 1, Config.height do
            for x = 1, Config.width do
                local index = (y - 1) * Config.width + x
                local neighbors = {}
                if x > 1 then neighbors[#neighbors + 1] = index - 1 end
                if x < Config.width then neighbors[#neighbors + 1] = index + 1 end
                if y > 1 then neighbors[#neighbors + 1] = index - Config.width end
                if y < Config.height then neighbors[#neighbors + 1] = index + Config.width end
                local matching = 0
                for _, neighbor in ipairs(neighbors) do
                    edges = edges + 1
                    if map.cells[index].kind == map.cells[neighbor].kind then
                        sameEdges, matching = sameEdges + 1, matching + 1
                    end
                end
                if matching == 0 then isolated = isolated + 1 end
            end
        end
        -- 不要求所有山地连成唯一一座山；检验绝大多数相邻格相连，排除棋盘噪声。
        assert(sameEdges / edges > 0.72, "地形过于零碎")
        assert(isolated <= 4, "出现太多独立单格地形")
    end
end)

add("高度与平原丘陵山地顺序一致", function()
    local map = Terrain.Generate(Config.defaultSeed, LandConfig)
    local low = { plain = 1, hill = 1, mountain = 1 }
    local high = { plain = 0, hill = 0, mountain = 0 }
    for _, cell in ipairs(map.cells) do
        low[cell.kind] = math.min(low[cell.kind], cell.elevation)
        high[cell.kind] = math.max(high[cell.kind], cell.elevation)
    end
    assert(low.plain == 0 and high.mountain == 1, "高度未归一化")
    assert(high.plain <= low.hill and high.hill <= low.mountain, "地形类型与高度顺序冲突")
end)

add("单格单行和极小地图均能退化生成", function()
    for _, size in ipairs({ {1, 1}, {1, 2}, {3, 1}, {2, 2}, {2, 3}, {1, 14}, {17, 1}, {3, 7} }) do
        local config = configWith({ width = size[1], height = size[2] })
        for seed = 1, 6 do validateMap(Terrain.Generate(seed, config), config) end
    end
end)

add("地形参数来自配置且山地仍可居住迁移", function()
    local plain, hill, mountain = Terrain.Profile("plain", Config), Terrain.Profile("hill", Config), Terrain.Profile("mountain", Config)
    assert(plain.capacityMultiplier == Config.terrainPlainCapacity and plain.migrationMultiplier == Config.terrainPlainMigration)
    assert(hill.capacityMultiplier == Config.terrainHillCapacity and hill.migrationMultiplier == Config.terrainHillMigration)
    assert(mountain.capacityMultiplier == Config.terrainMountainCapacity and mountain.migrationMultiplier == Config.terrainMountainMigration)
    assert(plain.capacityMultiplier > hill.capacityMultiplier and hill.capacityMultiplier > mountain.capacityMultiplier)
    assert(plain.migrationMultiplier > hill.migrationMultiplier and hill.migrationMultiplier > mountain.migrationMultiplier)
    assert(mountain.capacityMultiplier > 0 and mountain.migrationMultiplier > 0, "山地不得成为不可居住或不可迁移格")
    local custom = configWith({ terrainMountainCapacity = 0.8, terrainHillMigration = 0.6 })
    assert(Terrain.Profile("mountain", custom).capacityMultiplier == 0.8)
    assert(Terrain.Profile("hill", custom).migrationMultiplier == 0.6)
end)

add("关闭地形影响时全平原且所有乘数为一", function()
    local config = configWith({ terrainEnabled = false })
    local map = Terrain.Generate(91, config)
    validateMap(map, config)
    for _, cell in ipairs(map.cells) do assert(cell.kind == "plain" and cell.elevation == 0) end
    for _, kind in ipairs({ "plain", "hill", "mountain" }) do
        local profile = Terrain.Profile(kind, config)
        assert(profile.capacityMultiplier == 1 and profile.migrationMultiplier == 1)
    end
end)

add("地形不依赖全局随机数也不改变地区布局", function()
    local Regions = require("OriginRegions")
    local expectedTerrain, expectedRegions = Terrain.Generate(27183, Config), Regions.Generate(27183, Config)
    local oldRandom, oldSeed = math.random, math.randomseed
    math.random = function() error("不得使用全局随机数") end
    math.randomseed = function() error("不得修改全局随机数种子") end
    local ok, failure = pcall(function()
        same(Terrain.Generate(27183, Config), expectedTerrain)
        Terrain.Generate(82711, Config)
        same(Regions.Generate(27183, Config), expectedRegions)
    end)
    math.random, math.randomseed = oldRandom, oldSeed
    assert(ok, failure)
end)

add("生成与参数返回值不修改配置或共享颜色", function()
    local config = configWith()
    local expected = Terrain.Generate(531, config)
    local changed = Terrain.Generate(531, config)
    changed.cells[1].kind, changed.cells[1].elevation = "mountain", -1
    local profile = Terrain.Profile("plain", config)
    local expectedColor = profile.color[1]
    profile.color[1] = -1
    assert(Terrain.Profile("plain", config).color[1] == expectedColor)
    same(config, Config)
    same(Terrain.Generate(531, config), expected)
end)

add("一千种子均为陆地且比例严格达标", function()
    for seed = 1, 1000 do validateMap(Terrain.Generate(seed * 7919, Config), Config) end
end)

add("宽高一至十二与长条地图保持严格比例", function()
    for width = 1, 12 do
        for height = 1, 12 do
            local config = configWith({width = width, height = height})
            for seed = 1, 8 do validateMap(Terrain.Generate(seed * 104729, config), config) end
        end
    end
    for _, size in ipairs({{1,24}, {24,1}, {2,64}, {64,2}, {3,80}, {80,3},
        {4,16}, {16,4}, {7,9}, {9,7}, {16,24}, {24,16}, {32,48}, {48,32}}) do
        local config = configWith({width = size[1], height = size[2]})
        for seed = 1, 24 do validateMap(Terrain.Generate(seed * 15485863, config), config) end
    end
end)

add("拒绝非法种子尺寸类型及阻断迁移参数", function()
    assert(not pcall(Terrain.Generate, 0.5 --[[@as integer]], Config))
    assert(not pcall(Terrain.Generate, 1, configWith({ width = 0 })))
    assert(not pcall(Terrain.Generate, 1, configWith({ height = 1.5 })))
    assert(not pcall(Terrain.Profile, "ocean" --[[@as OriginTerrainKind]], Config))
    assert(not pcall(Terrain.Profile, "mountain", configWith({ terrainMountainMigration = 0 })))
    assert(not pcall(Terrain.Profile, "hill", configWith({ terrainHillCapacity = -1 })))
end)

---@return table
function Tests.Run()
    constraints = {allMaps = newConstraintRange(), defaultSizeEnabled = newConstraintRange()}
    local report = { passed = 0, failed = 0, total = #cases, ok = false, results = {},
        terrainConstraints = constraints }
    for _, case in ipairs(cases) do
        local ok, message = pcall(case.run)
        report.results[#report.results + 1] = { name = case.name, passed = ok, error = not ok and tostring(message) or nil }
        if ok then report.passed = report.passed + 1 else report.failed = report.failed + 1 end
        print("[OriginTerrainTests] " .. (ok and "通过 " or "失败 ") .. case.name .. (ok and "" or "：" .. tostring(message)))
    end
    report.ok = report.failed == 0
    print(string.format("[OriginTerrainTests] 总计 %d，通过 %d，失败 %d", report.total, report.passed, report.failed))
    return report
end

return Tests
