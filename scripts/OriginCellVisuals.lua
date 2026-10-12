-- 地块信息图：只读取当期指标，不参与模拟，也不按地区或种子装饰。
local Visuals = {}
-- 固定刻度，六档布局不要求各档等距；不能随地图当期均值漂移。
Visuals.FoodThresholds = {0.01, 0.33, 0.66, 1.0, 1.25, 1.5}
-- 温饱线附近的渐变宽度：越小越陡，改变它不影响数量档位或模拟。
Visuals.FoodColorTransitionWidth = 0.03

---@class OriginCellGlyph
---@field x number
---@field y number
---@field size number

---@class OriginFoodGlyph
---@field x number
---@field y number
---@field width number
---@field height number

---@class OriginCellGlyphLayout
---@field food OriginFoodGlyph[]
---@field houses OriginCellGlyph[]
---@field roses OriginCellGlyph[]

local function clamp(value, low, high) return math.max(low, math.min(high, value)) end

---@param population number
---@param foodPerCapita number 每人每世代消耗1单位食物，因此等于温饱比
---@param craftPerCapita number
---@param initialCraftPerCapita number 固定开局基准，不能使用当期全图均值
---@return table
function Visuals.State(population, foodPerCapita, craftPerCapita, initialCraftPerCapita)
    local food = math.max(0, foodPerCapita)
    -- 每个阈值是一块长方形的起点；低于0.01不显示农业块。
    local foodBlocks = 0
    for _, threshold in ipairs(Visuals.FoodThresholds) do
        if food + 1e-9 >= threshold then foodBlocks = foodBlocks + 1 end
    end
    -- 以温饱线为中心的S形曲线：远端变化缓慢，接近1时快速而连续。
    local nourishment = 1 / (1 + math.exp(-2 * (food - 1) / Visuals.FoodColorTransitionWidth))
    local red, amber, green = {219, 83, 48}, {225, 174, 65}, {74, 145, 76}
    -- 1处两段都为黄色；缺粮一侧不混入绿色，盈余一侧迅速向绿过渡。
    local from, to = food < 1 and red or amber, food < 1 and amber or green
    local blend = food < 1 and nourishment * 2 or (nourishment - 0.5) * 2
    local foodColor = {from[1] + (to[1] - from[1]) * blend,
        from[2] + (to[2] - from[2]) * blend, from[3] + (to[3] - from[3]) * blend, 255}
    local craftRatio = initialCraftPerCapita > 0 and math.max(0, craftPerCapita) / initialCraftPerCapita or 0
    return {foodBlocks = foodBlocks, foodColor = foodColor,
        roses = clamp(math.floor(craftRatio * 2 + 1e-9), 0, 6),
        houses = clamp(math.ceil(math.max(0, population) / 15), 0, 6)}
end

---@param cw number
---@param ch number
---@return OriginCellGlyphLayout
function Visuals.Layout(cw, ch)
    ---@type OriginCellGlyphLayout
    local layout = {food = {}, houses = {}, roses = {}}
    local blockWidth, blockHeight, gap = cw * 0.25, ch * 0.095, ch * 0.035
    for i = 1, 6 do
        layout.food[i] = {x = cw * 0.065, y = ch * 0.85 - blockHeight - (i - 1) * (blockHeight + gap),
            width = blockWidth, height = blockHeight}
    end
    for i = 1, 6 do
        local column, row = (i - 1) % 3, (i - 1) // 3
        layout.houses[i] = {x = cw * (0.40 + column * 0.19), y = ch * (0.27 + row * 0.23), size = cw * 0.48}
        -- 玫瑰由右下方的下排开始增多，再增加上排。
        layout.roses[i] = {x = cw * (0.46 + column * 0.20), y = ch * (0.87 - row * 0.18), size = cw * 0.034}
    end
    return layout
end

return Visuals
