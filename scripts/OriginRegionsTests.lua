-- 地区生成的纯 Lua 测试；require 不运行，显式调用 Tests.Run()。
local Regions = require("OriginRegions")
local Config = require("OriginConfig")
local Tests = {}

---@class OriginRegionTestCase
---@field name string
---@field run fun()

---@type OriginRegionTestCase[]
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

---@param a any
---@param b any
local function same(a, b)
    assert(type(a) == type(b), "重放类型不一致")
    if type(a) ~= "table" then assert(a == b, "重放数值不一致") return end
    for key, value in pairs(a) do same(value, b[key]) end
    for key in pairs(b) do assert(a[key] ~= nil, "重放多出字段") end
end

---@param map OriginRegionMap
---@param config OriginParameters
local function validatePartition(map, config)
    local width, height = config.width, config.height
    local count = width * height
    assert(#map.regions == math.min(4, count), "地区数错误")
    assert(#map.cellRegionIds == count, "地图没有全部覆盖")
    local covered, kinds = {}, {}
    for id, region in ipairs(map.regions) do
        assert(region.id == id and #region.indices > 0, "地区为空或编号错误")
        assert(not kinds[region.kind], "类型重复")
        kinds[region.kind] = true
        assert(region.name ~= "" and region.description ~= "", "缺少名称或说明")
        local anchor = (region.anchorY - 1) * width + region.anchorX
        assert(map.cellRegionIds[anchor] == id, "代表点不在所属地区")
        local members = {}
        for _, index in ipairs(region.indices) do
            assert(index >= 1 and index <= count and math.tointeger(index), "索引越界")
            assert(not covered[index], "地区重复覆盖")
            assert(map.cellRegionIds[index] == id, "正反归属不一致")
            covered[index], members[index] = true, true
        end
        -- 从代表点做四邻域 BFS，禁止通过对角相接伪装成连通。
        local queue, reached, cursor = { anchor }, { [anchor] = true }, 1
        while cursor <= #queue do
            local index = queue[cursor]
            cursor = cursor + 1
            local x, y = (index - 1) % width + 1, (index - 1) // width + 1
            local neighbors = {}
            if x > 1 then neighbors[#neighbors + 1] = index - 1 end
            if x < width then neighbors[#neighbors + 1] = index + 1 end
            if y > 1 then neighbors[#neighbors + 1] = index - width end
            if y < height then neighbors[#neighbors + 1] = index + width end
            for _, neighbor in ipairs(neighbors) do
                if members[neighbor] and not reached[neighbor] then
                    reached[neighbor] = true
                    queue[#queue + 1] = neighbor
                end
            end
        end
        assert(#queue == #region.indices, "地区不满足四邻域连通")
    end
    for index = 1, count do assert(covered[index], "存在未覆盖格子") end
    if count >= 4 then
        assert(kinds.agriculture and kinds.craft and kinds.population and kinds.frontier, "未覆盖四种特点")
    end
end

---@param map OriginRegionMap
---@return string
local function layoutSignature(map)
    return table.concat(map.cellRegionIds, ",")
end

---@param map OriginRegionMap
---@return string
local function kindSignature(map)
    local parts = {}
    for _, region in ipairs(map.regions) do parts[#parts + 1] = region.kind end
    return table.concat(parts, ",")
end

---@param values OriginRegionInitialValues
---@param config OriginParameters
local function validateValues(values, config)
    local ranges = {
        { "k", config.capacityMin, config.capacityMax },
        { "a", config.agricultureMin, config.agricultureMax },
        { "b", config.craftMin, config.craftMax },
        { "f", config.initialFoodShareMin, config.initialFoodShareMax },
        { "noise", config.populationNoiseMin, config.populationNoiseMax },
    }
    for _, range in ipairs(ranges) do
        local value = values[range[1]]
        assert(value >= range[2] and value <= range[3], "初始参数越界：" .. range[1])
    end
    assert(values.k * (values.a * values.f - 1) * values.noise > 0, "初始人口应为正")
end

add("相同种子精确重放地区与标签", function()
    for _, seed in ipairs({ Config.defaultSeed, 1, 0, -7, 2147483647 }) do
        same(Regions.Generate(seed, Config), Regions.Generate(seed, Config))
    end
end)

add("不同种子改变轮廓与类型位置", function()
    local first = Regions.Generate(Config.defaultSeed, Config)
    local shape, kinds = layoutSignature(first), kindSignature(first)
    local shapeChanged, kindsChanged = false, false
    for offset = 1, 8 do
        local map = Regions.Generate(Config.defaultSeed + offset, Config)
        shapeChanged = shapeChanged or layoutSignature(map) ~= shape
        kindsChanged = kindsChanged or kindSignature(map) ~= kinds
    end
    assert(shapeChanged and kindsChanged, "种子没有改变轮廓与类型位置")
end)

add("多种子完整覆盖且每区四邻域连通", function()
    for seed = 1, 48 do validatePartition(Regions.Generate(seed * 7919, Config), Config) end
end)

add("地区轮廓不是四个固定矩形", function()
    local map = Regions.Generate(Config.defaultSeed, Config)
    local irregular = 0
    for _, region in ipairs(map.regions) do
        local left, right, top, bottom = Config.width, 1, Config.height, 1
        for _, index in ipairs(region.indices) do
            local x, y = (index - 1) % Config.width + 1, (index - 1) // Config.width + 1
            left, right = math.min(left, x), math.max(right, x)
            top, bottom = math.min(top, y), math.max(bottom, y)
        end
        if (right - left + 1) * (bottom - top + 1) > #region.indices then irregular = irregular + 1 end
    end
    assert(irregular >= 3, "默认地图需要有可辨认的不规则边界")
end)

add("小地图与单行单列可退化为一至四区", function()
    for _, size in ipairs({ {1, 1}, {1, 2}, {3, 1}, {1, 4}, {2, 2}, {2, 3}, {1, 12}, {13, 1}, {3, 7} }) do
        local config = configWith({ width = size[1], height = size[2] })
        for seed = 1, 8 do validatePartition(Regions.Generate(seed, config), config) end
    end
end)

add("扰动边界与窄配置不扩大原参数范围", function()
    local configs = { Config, configWith({
        capacityMin = 40, capacityMax = 40,
        agricultureMin = 3.0, agricultureMax = 3.05,
        craftMin = 2.0, craftMax = 2.02,
        initialFoodShareMin = 0.58, initialFoodShareMax = 0.60,
        populationNoiseMin = 0.97, populationNoiseMax = 1.03,
    }) }
    for _, config in ipairs(configs) do
        local map = Regions.Generate(8871, config)
        for _, region in ipairs(map.regions) do
            for _, sample in ipairs({0, 0.5, 1}) do
                local values = Regions.InitialValues(region, { sample, sample, sample, sample, sample }, config)
                validateValues(values, config)
            end
        end
    end
end)

add("四类地区有实测参数与温饱差异", function()
    local map = Regions.Generate(Config.defaultSeed, Config)
    local means = {}
    for _, region in ipairs(map.regions) do
        local totals = { k = 0, a = 0, b = 0, f = 0, n = 0, food = 0, craft = 0 }
        for _, index in ipairs(region.indices) do
            -- 与生成器不同的固定扰动序列，避免只核对常数表。
            local samples = {}
            for channel = 1, 5 do samples[channel] = ((index * 53 + channel * 97) % 997) / 996 end
            local value = Regions.InitialValues(region, samples, Config)
            validateValues(value, Config)
            local n = value.k * (value.a * value.f - 1) * value.noise
            totals.k, totals.a = totals.k + value.k, totals.a + value.a
            totals.b, totals.f = totals.b + value.b, totals.f + value.f
            totals.n = totals.n + n
            totals.food = totals.food + value.a * value.f / (1 + n / value.k)
            totals.craft = totals.craft + value.b * (1 - value.f) / (1 + n / value.k)
        end
        for key, value in pairs(totals) do totals[key] = value / #region.indices end
        means[region.kind] = totals
    end
    local agriculture, craft, population, frontier = means.agriculture, means.craft, means.population, means.frontier
    assert(agriculture.a > population.a and agriculture.a > craft.a, "农业区效率没有优势")
    assert(agriculture.food > 1.01, "农业区没有少量余粮")
    assert(craft.b > population.b and craft.b > agriculture.b, "工艺区效率没有优势")
    assert(craft.f < frontier.f and craft.craft > agriculture.craft, "工艺区应务农较少、用品较多")
    assert(population.k > agriculture.k and population.n > agriculture.n, "人密区人口与容量应较高")
    assert(population.food < 0.99, "人密区应略超温饱平衡")
    assert(frontier.k < craft.k and frontier.n < craft.n and frontier.n < agriculture.n, "边地应人口与容量较低")
end)

add("生成不读写全局随机数", function()
    local expected = Regions.Generate(42157, Config)
    local originalRandom, originalSeed = math.random, math.randomseed
    math.random = function() error("不允许使用 math.random") end
    math.randomseed = function() error("不允许使用 math.randomseed") end
    local ok, failure = pcall(function()
        same(Regions.Generate(42157, Config), expected)
        Regions.InitialValues(expected.regions[1], {0.1, 0.3, 0.5, 0.7, 0.9}, Config)
    end)
    math.random, math.randomseed = originalRandom, originalSeed
    assert(ok, failure)
end)

add("生成结果独立且不修改配置与扰动输入", function()
    local config = configWith()
    local map = Regions.Generate(631, config)
    local expected = Regions.Generate(631, config)
    local samples = {0.2, 0.4, 0.6, 0.8, 1.0}
    Regions.InitialValues(map.regions[1], samples, config)
    same(config, Config)
    same(samples, {0.2, 0.4, 0.6, 0.8, 1.0})
    map.regions[1].color[1], map.regions[1].indices[1] = -1, -1
    same(Regions.Generate(631, config), expected)
end)

add("拒绝非法地图尺寸种子与扰动", function()
    assert(not pcall(Regions.Generate, 0.25 --[[@as integer]], Config))
    for _, overrides in ipairs({ {width = 0}, {height = -1}, {width = 2.5} }) do
        assert(not pcall(Regions.Generate, 1, configWith(overrides)))
    end
    local region = Regions.Generate(1, Config).regions[1]
    assert(not pcall(Regions.InitialValues, region, {-0.1, 0, 0, 0, 0}, Config))
    assert(not pcall(Regions.InitialValues, region, {0, 0, 0, 0, 1.1}, Config))
end)

---@return table
function Tests.Run()
    local report = { passed = 0, failed = 0, total = #cases, ok = false, results = {} }
    for _, case in ipairs(cases) do
        local ok, message = pcall(case.run)
        report.results[#report.results + 1] = { name = case.name, passed = ok, error = not ok and tostring(message) or nil }
        if ok then report.passed = report.passed + 1 else report.failed = report.failed + 1 end
        print("[OriginRegionsTests] " .. (ok and "通过 " or "失败 ") .. case.name .. (ok and "" or "：" .. tostring(message)))
    end
    report.ok = report.failed == 0
    print(string.format("[OriginRegionsTests] 总计 %d，通过 %d，失败 %d", report.total, report.passed, report.failed))
    return report
end

return Tests
