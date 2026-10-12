-- 当前选区的确定性建议：比较两轮内的温饱与用品改善，不修改世界或消耗随机数。
-- 只估算本地技术增长；人口迁移、邻格学习和制度竞争仍由正式模拟决定。
local S = require("OriginSimulation")
local R = {}
local ACTIONS = {"craft", "agriculture", "foodUp", "foodDown", "institution"}
local REASONS = {
    agriculture = "尝试提高农业效率，补足所选地块的食物。已按当前制度的成功率折算收益，失败仍占一轮。",
    craft = "尝试提高工艺效率，增加所选地块的生活用品。已按当前制度的成功率折算收益，失败仍占一轮。",
    foodUp = "把更多劳动分配给农业，优先改善温饱。",
    foodDown = "把更多劳动分配给制物，增加生活用品。",
    institution = "设立探索制度；按本局设置估算其农业、工艺自然增长收益。请同时留意改良成功率与制度竞争能力。",
}

---@param cell OriginCell
---@param world OriginWorld
---@param action string?
---@param horizon integer
---@return number
local function Score(cell, world, action, horizon)
    local cfg = world.config
    ---@type OriginCell
    local projected = {}
    for key, value in pairs(cell) do projected[key] = value end
    if action == "agriculture" then projected.agriculture = cell.agriculture * cfg.agricultureActionMultiplier
    elseif action == "craft" then projected.craft = cell.craft * cfg.craftActionMultiplier
    elseif action == "foodUp" then projected.foodShare = math.min(cfg.foodShareMax, cell.foodShare + cfg.foodActionStep)
    elseif action == "foodDown" then projected.foodShare = math.max(cfg.foodShareMin, cell.foodShare - cfg.foodActionStep)
    elseif action == "institution" then projected.institution = cfg.exploreInstitution end
    local growth = projected.institution == cfg.exploreInstitution and cfg.exploreCraftGrowth or cfg.mobilizeCraftGrowth
    local agricultureGrowth = projected.institution == cfg.exploreInstitution and cfg.exploreAgricultureGrowth or cfg.mobilizeAgricultureGrowth
    projected.agriculture = projected.agriculture * (1 + agricultureGrowth) ^ horizon
    projected.craft = projected.craft * (1 + growth) ^ horizon
    local metric = S.Metrics(projected, cfg)
    local food = math.min(1, metric.foodRatio / cfg.prosperousFoodRatio)
    local craft = math.min(1, metric.craftPerCapita / (world.baselineCraft * cfg.prosperousCraftMultiplier))
    return food ^ 8 * craft ^ 2
end

---@param world OriginWorld
---@param x integer
---@param y integer
---@param withProtection boolean?
---@return string?, string?
function R.Choose(world, x, y, withProtection)
    local cfg = world.config
    local horizon = math.min(2, cfg.rounds - world.round) * cfg.generationsPerRound
    ---@type string?
    local best = nil
    local highest = -math.huge
    for _, action in ipairs(ACTIONS) do
        if S.ValidateAction(world, action, x, y, withProtection) then
            local gain = 0.0
            for cy = y, y + cfg.regionSize - 1 do
                for cx = x, x + cfg.regionSize - 1 do
                    local cell = world.cells[(cy - 1) * cfg.width + cx]
                    if S.IsHabitable(cell) then
                        local probability = (action == "agriculture" or action == "craft")
                            and S.ImprovementProbability(cell, cfg) or 1
                        -- 分别评估成功与失败，再求期望；不窥探或推进模拟随机流。
                        gain = gain + probability * cell.population * (Score(cell, world, action, horizon) - Score(cell, world, nil, horizon))
                    end
                end
            end
            if gain > highest then best, highest = action, gain end
        end
    end
    return best, best and REASONS[best] or nil
end

return R
