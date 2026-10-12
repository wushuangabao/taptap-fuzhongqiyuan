-- 《富种起源》连续地形。只生成地形数据与参数，不修改人口或执行迁移。
-- 地区、地形、世界演化各用独立随机流；地形不按地区类型分配。
local DefaultConfig = require("OriginConfig")
local Terrain = {}

---@alias OriginTerrainKind "plain"|"hill"|"mountain"

---@class OriginTerrainCell
---@field kind OriginTerrainKind
---@field elevation number 相对高度，范围 [0,1]

---@class OriginTerrainMap
---@field version string
---@field cells OriginTerrainCell[]

---@class OriginTerrainProfile
---@field name string
---@field capacityMultiplier number
---@field migrationMultiplier number
---@field description string
---@field color number[]

---@class OriginTerrainStyle
---@field name string
---@field description string
---@field color number[]
---@field capacityKey string
---@field migrationKey string

---@type table<string, OriginTerrainStyle>
local STYLES = {
    plain = { name = "平原", description = "开阔的平地，适合聚居与往来。",
        color = { 140, 163, 113 }, capacityKey = "terrainPlainCapacity", migrationKey = "terrainPlainMigration" },
    hill = { name = "丘陵", description = "起伏的丘陵，人口往来受地形影响。",
        color = { 149, 141, 103 }, capacityKey = "terrainHillCapacity", migrationKey = "terrainHillMigration" },
    mountain = { name = "山地", description = "连绵的山地，仍可居住和迁移。",
        color = { 135, 141, 146 }, capacityKey = "terrainMountainCapacity", migrationKey = "terrainMountainMigration" },
}

---@param seed integer
---@param salt integer?
---@return fun():number
local function newRandom(seed, salt)
    -- 独立固定盐；乘法小于 2^53，不依赖平台整数溢出。
    local state = ((seed % 2147483647) + (salt or 524287)) % 2147483647
    if state == 0 then state = 1 end
    return function()
        state = (state * 16807) % 2147483647
        return (state - 1) / 2147483646
    end
end

---@param fraction number
---@return number
local function smooth(fraction)
    return fraction * fraction * (3 - 2 * fraction)
end

---@class OriginTerrainNoise
---@field spacing number
---@field columns integer
---@field offsetX number
---@field offsetY number
---@field values number[]

---@param width integer
---@param height integer
---@param spacing number
---@param random fun():number
---@return OriginTerrainNoise
local function noiseGrid(width, height, spacing, random)
    local columns = math.ceil(width / spacing) + 3
    local rows = math.ceil(height / spacing) + 3
    ---@type OriginTerrainNoise
    local grid = { spacing = spacing, columns = columns,
        offsetX = random() * spacing, offsetY = random() * spacing, values = {} }
    for index = 1, columns * rows do grid.values[index] = random() end
    return grid
end

---@param grid OriginTerrainNoise
---@param x integer
---@param y integer
---@return number
local function sampleNoise(grid, x, y)
    local gx = (x - 1 + grid.offsetX) / grid.spacing
    local gy = (y - 1 + grid.offsetY) / grid.spacing
    local left, top = math.floor(gx), math.floor(gy)
    local fx, fy = smooth(gx - left), smooth(gy - top)
    local topLeft = top * grid.columns + left + 1
    local bottomLeft = topLeft + grid.columns
    local upper = grid.values[topLeft] * (1 - fx) + grid.values[topLeft + 1] * fx
    local lower = grid.values[bottomLeft] * (1 - fx) + grid.values[bottomLeft + 1] * fx
    return upper * (1 - fy) + lower * fy
end

---@class OriginTerrainSample
---@field index integer
---@field value number

---@param seed integer
---@param config OriginParameters?
---@return OriginTerrainMap
function Terrain.Generate(seed, config)
    local cfg = config or DefaultConfig
    assert(math.tointeger(seed), "地形种子必须为整数")
    assert(math.tointeger(cfg.width) and cfg.width > 0
        and math.tointeger(cfg.height) and cfg.height > 0, "地形地图尺寸必须为正整数")
    local count = cfg.width * cfg.height
    ---@type OriginTerrainMap
    local map = { version = "origin-terrain-5", cells = {} }
    if cfg.terrainEnabled == false then
        for index = 1, count do map.cells[index] = { kind = "plain", elevation = 0 } end
        return map
    end
    local random = newRandom(seed)
    -- 主高度场横跨数格，次级场占10%，避免较窄的丘陵带出现零散单格。
    local spacing = math.max(4, math.min(cfg.width, cfg.height) * 0.50)
    local coarse = noiseGrid(cfg.width, cfg.height, spacing, random)
    local detail = noiseGrid(cfg.width, cfg.height, math.max(2, spacing * 0.50), random)
    ---@type OriginTerrainSample[]
    local samples = {}
    local low, high = math.huge, -math.huge
    for y = 1, cfg.height do
        for x = 1, cfg.width do
            local index = (y - 1) * cfg.width + x
            local value = sampleNoise(coarse, x, y) * 0.90 + sampleNoise(detail, x, y) * 0.10
            samples[index] = { index = index, value = value }
            low, high = math.min(low, value), math.max(high, value)
        end
    end
    -- 按总格数控制地形分位：平原至少68%、山地至多14%，严格低于15%。
    -- 微型地图允许没有山地或丘陵，不为凑齐类型牺牲最终比例。
    table.sort(samples, function(a, b)
        if a.value == b.value then return a.index < b.index end
        return a.value < b.value
    end)
    local plainCount = math.ceil(count * 0.68)
    local mountainCount = math.floor(count * 0.14)
    local hillCount = count - plainCount - mountainCount
    for rank, sample in ipairs(samples) do
        ---@type OriginTerrainKind
        local kind = rank <= plainCount and "plain" or (rank <= plainCount + hillCount and "hill" or "mountain")
        local elevation = high > low and (sample.value - low) / (high - low) or 0
        map.cells[sample.index] = { kind = kind, elevation = elevation }
    end
    return map
end

---@param kind OriginTerrainKind
---@param config OriginParameters?
---@return OriginTerrainProfile
function Terrain.Profile(kind, config)
    local cfg = config or DefaultConfig
    local style = assert(STYLES[kind], "未知地形类型：" .. tostring(kind))
    local enabled = cfg.terrainEnabled ~= false
    local capacity = enabled and cfg[style.capacityKey] or 1
    local migration = enabled and cfg[style.migrationKey] or 1
    assert(type(capacity) == "number" and capacity > 0 and capacity < math.huge, "地形承载量乘数无效")
    assert(type(migration) == "number" and migration > 0 and migration <= 1, "地形迁移乘数须在 (0,1] 内")
    return { name = style.name, capacityMultiplier = capacity, migrationMultiplier = migration,
        description = enabled and style.description or "地形影响已关闭，承载量与迁移均按基础规则计算。",
        color = { style.color[1], style.color[2], style.color[3] } }
end

return Terrain
