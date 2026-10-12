-- 《富种起源》开局地区。只生成归属与初始参数，不参与后续增长、迁移或行动。
-- 独立随机流保留世界模拟的抽样顺序；不依赖引擎、math.random 或系统时间。
local DefaultConfig = require("OriginConfig")
local Regions = {}

---@class OriginRegion
---@field id integer
---@field kind string
---@field name string
---@field description string
---@field anchorX integer
---@field anchorY integer
---@field indices integer[]
---@field color number[]
---@field hasHabitableLand boolean?

---@class OriginRegionMap
---@field regions OriginRegion[]
---@field cellRegionIds integer[]
---@field version string

---@class OriginRegionInitialValues
---@field k number
---@field a number
---@field b number
---@field f number
---@field noise number

---@class OriginRegionProfile
---@field kind string
---@field title string
---@field description string
---@field color number[]
---@field quantiles number[]

-- 分位数以原参数上下限为尺度，不扩大参数范围，也不是地区永久加成。
-- 顺序：土地容量、农业效率、工艺效率、务农比例、相对平衡人口的扰动。
---@type OriginRegionProfile[]
local PROFILES = {
    { kind = "agriculture", title = "丰禾乡", color = { 194, 178, 105 },
        description = "同地形下开局农业较强、人口略低于温饱平衡，食物有少量余裕。",
        quantiles = { 0.56, 0.85, 0.35, 0.70, 0.15 } },
    { kind = "craft", title = "百工镇", color = { 137, 177, 202 },
        description = "同地形下开局工艺较强、务农较少，生活用品生产更有基础。",
        quantiles = { 0.48, 0.42, 0.88, 0.12, 0.42 } },
    { kind = "population", title = "万家聚", color = { 200, 143, 129 },
        description = "同地形下开局土地容量与人口较多，人口略超温饱平衡。",
        quantiles = { 0.90, 0.55, 0.52, 0.60, 0.88 } },
    { kind = "frontier", title = "疏居地", color = { 138, 170, 145 },
        description = "同地形下开局土地容量与人口较少，农艺和工艺基础较弱。",
        quantiles = { 0.10, 0.18, 0.20, 0.35, 0.35 } },
}

---@param seed integer
---@return fun():number
local function newRandom(seed)
    -- 以固定盐区分模拟随机流。乘法小于 2^53，Lua 整数与浮点实现均可精确计算。
    local state = ((seed % 2147483647) + 104729) % 2147483647
    if state == 0 then state = 1 end
    return function()
        state = (state * 16807) % 2147483647
        return (state - 1) / 2147483646
    end
end

---@param index integer
---@param width integer
---@return integer, integer
local function coordinates(index, width)
    return (index - 1) % width + 1, (index - 1) // width + 1
end

---@param low integer
---@param high integer
---@param random fun():number
---@return integer
local function innerCoordinate(low, high, random)
    local inset = math.floor((high - low) * 0.20)
    return low + inset + math.floor(random() * (high - low - inset * 2 + 1))
end

---@param width integer
---@param height integer
---@param random fun():number
---@return integer[]
local function seedIndices(width, height, random)
    local seeds = {}
    if width >= 2 and height >= 2 then
        local splitX, splitY = width // 2, height // 2
        local boxes = {
            { 1, splitX, 1, splitY }, { splitX + 1, width, 1, splitY },
            { 1, splitX, splitY + 1, height }, { splitX + 1, width, splitY + 1, height },
        }
        for _, box in ipairs(boxes) do
            local x = innerCoordinate(box[1], box[2], random)
            local y = innerCoordinate(box[3], box[4], random)
            seeds[#seeds + 1] = (y - 1) * width + x
        end
    else
        -- 单行/单列夹具按线段分层取点；1 至 3 格不会产生空地区。
        local count = math.min(4, width * height)
        for id = 1, count do
            local low = math.floor((id - 1) * width * height / count) + 1
            local high = math.floor(id * width * height / count)
            seeds[#seeds + 1] = innerCoordinate(low, high, random)
        end
    end
    return seeds
end

---@class OriginRegionFrontier
---@field index integer
---@field regionId integer
---@field distance number
---@field order integer

---@param a OriginRegionFrontier
---@param b OriginRegionFrontier
---@return boolean
local function before(a, b)
    if a.distance == b.distance then return a.order < b.order end
    return a.distance < b.distance
end

---@param heap OriginRegionFrontier[]
---@param entry OriginRegionFrontier
local function push(heap, entry)
    local index = #heap + 1
    while index > 1 do
        local parent = index // 2
        if not before(entry, heap[parent]) then break end
        heap[index], index = heap[parent], parent
    end
    heap[index] = entry
end

---@param heap OriginRegionFrontier[]
---@return OriginRegionFrontier
local function pop(heap)
    local first, last = assert(heap[1]), assert(heap[#heap])
    heap[#heap] = nil
    if #heap > 0 then
        local index = 1
        while index * 2 <= #heap do
            local child = index * 2
            if child < #heap and before(heap[child + 1], heap[child]) then child = child + 1 end
            if not before(heap[child], last) then break end
            heap[index], index = heap[child], child
        end
        heap[index] = last
    end
    return first
end

---@param x integer
---@param y integer
---@param width integer
---@param height integer
---@return string
local function directionName(x, y, width, height)
    local horizontal = x < (width + 1) * 0.40 and "西" or (x > (width + 1) * 0.60 and "东" or "")
    local vertical = y < (height + 1) * 0.40 and "北" or (y > (height + 1) * 0.60 and "南" or "")
    local direction = horizontal .. vertical
    return direction == "" and "中部" or direction
end

---@param seed integer
---@param config OriginParameters?
---@return OriginRegionMap
function Regions.Generate(seed, config)
    local cfg = config or DefaultConfig
    assert(math.tointeger(seed), "地区种子必须为整数")
    assert(math.tointeger(cfg.width) and cfg.width > 0
        and math.tointeger(cfg.height) and cfg.height > 0, "地区地图尺寸必须为正整数")
    local width, height = cfg.width, cfg.height
    local random = newRandom(seed)
    -- 先洗牌再生成轮廓，让地区特点在不同种子下换位置。
    ---@type integer[]
    local profiles = { 1, 2, 3, 4 }
    for i = #profiles, 2, -1 do
        local j = 1 + math.floor(random() * i)
        profiles[i], profiles[j] = profiles[j], profiles[i]
    end
    local seeds = seedIndices(width, height, random)
    ---@type OriginRegionMap
    local map = { regions = {}, cellRegionIds = {}, version = "origin-regions-1" }
    local costs = {}
    for index = 1, width * height do costs[index] = 0.65 + random() * 0.80 end
    ---@type OriginRegionFrontier[]
    local heap = {}
    for id, index in ipairs(seeds) do
        local profileId = assert(profiles[id])
        local profile = assert(PROFILES[profileId])
        local x, y = coordinates(index, width)
        map.regions[id] = { id = id, kind = profile.kind, name = "", description = profile.description,
            anchorX = x, anchorY = y, indices = {},
            color = { profile.color[1], profile.color[2], profile.color[3] } }
        push(heap, { index = index, regionId = id, distance = 0, order = id })
    end
    local order = #seeds
    -- 每个新格只从已归属的四邻格生长，因而每片地区始终连通。
    -- 随机正代价让边界弯曲；这是地图生成参数，不是迁移/传播的移动代价。
    while #heap > 0 do
        local entry = pop(heap)
        if not map.cellRegionIds[entry.index] then
            map.cellRegionIds[entry.index] = entry.regionId
            local region = map.regions[entry.regionId]
            region.indices[#region.indices + 1] = entry.index
            local x, y = coordinates(entry.index, width)
            local neighbors = {}
            if x > 1 then neighbors[#neighbors + 1] = entry.index - 1 end
            if x < width then neighbors[#neighbors + 1] = entry.index + 1 end
            if y > 1 then neighbors[#neighbors + 1] = entry.index - width end
            if y < height then neighbors[#neighbors + 1] = entry.index + width end
            for _, neighbor in ipairs(neighbors) do
                if not map.cellRegionIds[neighbor] then
                    order = order + 1
                    push(heap, { index = neighbor, regionId = entry.regionId,
                        distance = entry.distance + costs[neighbor], order = order })
                end
            end
        end
    end
    for _, region in ipairs(map.regions) do
        -- 标签放在属于该区且最接近质心的格子；凹形地区也不会把标签放到别区。
        table.sort(region.indices)
        local sumX, sumY = 0, 0
        for _, index in ipairs(region.indices) do
            local x, y = coordinates(index, width)
            sumX, sumY = sumX + x, sumY + y
        end
        local centerX, centerY = sumX / #region.indices, sumY / #region.indices
        local bestDistance = math.huge
        for _, index in ipairs(region.indices) do
            local x, y = coordinates(index, width)
            local distance = (x - centerX)^2 + (y - centerY)^2
            if distance < bestDistance then
                region.anchorX, region.anchorY, bestDistance = x, y, distance
            end
        end
        local profileId = assert(profiles[region.id])
        local title = assert(PROFILES[profileId]).title
        region.name = directionName(region.anchorX, region.anchorY, width, height) .. title
    end
    return map
end

---@param low number
---@param high number
---@param quantile number
---@param sample number
---@return number
local function sampleRange(low, high, quantile, sample)
    assert(type(sample) == "number" and sample >= 0 and sample <= 1, "地区扰动须在 [0,1] 内")
    local position = math.max(0, math.min(1, quantile + (sample - 0.5) * 0.18))
    return low + (high - low) * position
end

-- noiseValues 由调用者传入，每格仍使用模拟原有的 5 次抽样，不额外抽样。
-- 初始人口由调用方按 k * (a * f - 1) * noise 计算。
---@param region OriginRegion
---@param noiseValues number[]
---@param config OriginParameters?
---@return OriginRegionInitialValues
function Regions.InitialValues(region, noiseValues, config)
    local cfg = config or DefaultConfig
    ---@type OriginRegionProfile?
    local profile = nil
    for _, candidate in ipairs(PROFILES) do
        if candidate.kind == region.kind then profile = candidate break end
    end
    assert(profile, "未知地区类型：" .. tostring(region.kind))
    local q = profile.quantiles
    return {
        k = sampleRange(cfg.capacityMin, cfg.capacityMax, q[1], noiseValues[1]),
        a = sampleRange(cfg.agricultureMin, cfg.agricultureMax, q[2], noiseValues[2]),
        b = sampleRange(cfg.craftMin, cfg.craftMax, q[3], noiseValues[3]),
        f = sampleRange(cfg.initialFoodShareMin, cfg.initialFoodShareMax, q[4], noiseValues[4]),
        noise = sampleRange(cfg.populationNoiseMin, cfg.populationNoiseMax, q[5], noiseValues[5]),
    }
end

return Regions
