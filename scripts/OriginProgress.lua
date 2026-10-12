-- 纯数据反馈：里程碑按历史最高值保留；胜利仍使用当期占比的连续达标判定。
local P = {}
P.Local = require("OriginLocalMilestones")
P.milestones = {
    {share = 0.10, title = "点亮核心"},
    {share = 0.30, title = "繁荣扩散"},
    {share = 0.60, title = "灯火成网"},
}

---@param peak number
---@return integer
function P.Level(peak)
    local level = 0
    for i, milestone in ipairs(P.milestones) do
        if peak >= milestone.share then level = i end
    end
    return level
end

---@param metric OriginMetric
---@param world OriginWorld
---@return string
function P.CellNeed(metric, world)
    local food = metric.foodRatio >= world.config.prosperousFoodRatio
    local craft = metric.craftPerCapita >= world.baselineCraft * world.config.prosperousCraftMultiplier
    if food and craft then return "已繁荣 · 稳住温饱与用品" end
    if craft then return "用品已达标 · 还差温饱" end
    if food then return "温饱已达标 · 还差生活用品" end
    return "粮食与生活用品都不足"
end

---@param summary OriginSummary
---@return string
function P.Advice(summary)
    if summary.won then return "全面现代化已达成" end
    if summary.prosperousStreak > 0 then return "繁荣正在持续，留意食物余量" end
    if summary.foodShortfallShare >= 0.10 then return "用品达标地区仍缺粮，可补足农业" end
    if summary.round <= 12 and summary.exploreShare < 0.30 then return "查看两种制度的增长、改良概率与竞争实力，因地制宜" end
    if summary.bothShortfallShare >= 0.20 then return "部分地区双缺，先稳住温饱" end
    return "培育探索核心，让工艺向周边传播"
end

return P
