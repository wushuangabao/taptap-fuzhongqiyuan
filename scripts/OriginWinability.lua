-- 通关能力验证：只调用正式模型；不改玩法、胜利条件或随机序列。
-- require 不自动执行。离线 Lua 5.4 调用 Run(seed, policy, choiceSeed, plan)。
local S = require("OriginSimulation")
local W = {}

W.policies = { "craft_focus", "craft_spread", "agriculture_spread", "institution_spread",
    "institution_strong", "reform_then_craft", "balanced", "random" }

local function position(world, rng)
    local size = world.config.regionSize
    return S.RandomInteger(rng, 1, world.width - size + 1), S.RandomInteger(rng, 1, world.height - size + 1)
end

-- 行动已到上限时，有限扫描合法区域。
---@param world OriginWorld
---@param preferred OriginActionRecord
---@return OriginActionRecord
local function legalChoice(world, preferred)
    if S.ValidateAction(world, preferred.action, preferred.x, preferred.y) then return preferred end
    local actions = preferred.action == "craft" and { "craft" } or { preferred.action, "craft" }
    for _, action in ipairs(actions) do
        for y = 1, world.height - world.config.regionSize + 1 do
            for x = 1, world.width - world.config.regionSize + 1 do
                if S.ValidateAction(world, action, x, y) then return { action = action, x = x, y = y } end
            end
        end
    end
    error("当前世界没有可执行的合法策略行动")
end

local function regionScore(world, action, x, y, mode)
    local score = 0.0
    local remaining = (world.config.rounds - world.round) * world.config.generationsPerRound
    local target = world.baselineCraft * world.config.prosperousCraftMultiplier
    for cy = y, y + world.config.regionSize - 1 do
        for cx = x, x + world.config.regionSize - 1 do
            local i = (cy - 1) * world.width + cx
            local c, m = world.cells[i], world.metrics[i]
            if S.IsHabitable(c) then
                if action == "institution" and c.institution ~= world.config.exploreInstitution then
                    local strongest = 0.0
                    for _, j in ipairs(world.neighbors[i]) do
                        strongest = math.max(strongest, world.metrics[j].power)
                    end
                    local survival = strongest > 0 and math.min(1.0, world.config.explorePowerMultiplier
                        / world.config.mobilizePowerMultiplier * m.power / strongest) or 1.0
                    score = score + c.population * (mode == "strong" and survival ^ 4 or 1.0)
                elseif action ~= "institution" then
                    local before = math.min(1, m.foodRatio) ^ 8 * math.min(1, m.craftPerCapita / target) ^ 2
                    local a, b, f = c.agriculture, c.craft, c.foodShare
                    if action == "craft" then b = b * world.config.craftActionMultiplier
                    elseif action == "agriculture" then a = a * world.config.agricultureActionMultiplier
                    elseif action == "foodDown" then f = math.max(world.config.foodShareMin, f - world.config.foodActionStep)
                    elseif action == "foodUp" then f = math.min(world.config.foodShareMax, f + world.config.foodActionStep)
                    end
                    local denominator = 1 + c.population / c.landCapacity
                    local after = math.min(1, a * f / denominator) ^ 8
                        * math.min(1, b * (1 - f) / denominator / target) ^ 2
                    local probability = (action == "craft" or action == "agriculture")
                        and S.ImprovementProbability(c, world.config) or 1
                    score = score + probability * c.population * (after - before)
                    if action == "craft" and remaining > 25 and c.institution == world.config.exploreInstitution then
                        local growthAdvantage = math.max(0, world.config.exploreCraftGrowth - world.config.mobilizeCraftGrowth)
                        score = score + probability * c.population * growthAdvantage
                    end
                end
            end
        end
    end
    return score
end

local function bestRegion(world, actions, mode)
    ---@type OriginActionRecord?
    local best = nil
    local highest = -math.huge
    for _, action in ipairs(actions) do
        for y = 1, world.height - world.config.regionSize + 1 do
            for x = 1, world.width - world.config.regionSize + 1 do
                if S.ValidateAction(world, action, x, y) then
                    local score = regionScore(world, action, x, y, mode)
                    assert(S.IsFinite(score), "策略区域评分不是有限数")
                    if score > highest then
                        highest, best = score, { action = action, x = x, y = y }
                    end
                end
            end
        end
    end
    return best or legalChoice(world, { action = "craft", x = 1, y = 1 })
end

function W.Choose(world, policy, rng)
    local round = world.round + 1
    local size = world.config.regionSize
    if policy == "craft_focus" then
        return legalChoice(world, { action = "craft", x = (world.width - size) // 2 + 1, y = (world.height - size) // 2 + 1 })
    end
    if policy == "craft_spread" or policy == "agriculture_spread" then
        local columns = (world.width - 1) // size + 1
        local rows = (world.height - 1) // size + 1
        return legalChoice(world, { action = policy == "craft_spread" and "craft" or "agriculture",
            x = math.min(world.width - size + 1, 1 + ((round - 1) % columns) * size),
            y = math.min(world.height - size + 1, 1 + (((round - 1) // columns) % rows) * size) })
    end
    if policy == "institution_spread" then return bestRegion(world, { "institution" }, "population") end
    if policy == "institution_strong" then return bestRegion(world, { "institution" }, "strong") end
    if policy == "reform_then_craft" or policy == "balanced" then
        if round <= math.floor(world.config.rounds * 0.6) then return bestRegion(world, { "institution" }, "strong") end
        return bestRegion(world, policy == "balanced"
            and { "craft", "agriculture", "foodDown", "foodUp" } or { "craft" }, "gain")
    end
    assert(policy == "random", "unknown policy")
    local names = { "agriculture", "craft", "foodUp", "foodDown", "institution", "protect" }
    local action = names[S.RandomInteger(rng, 1, #names)]
    local x, y = position(world, rng)
    if not S.ValidateAction(world, action, x, y) then action = "craft" end
    return legalChoice(world, { action = action, x = x, y = y })
end

local function summarize(world, curve, policy, choiceSeed, maxError)
    local final = S.Statistics(world)
    local bestFive, peakGeneration = 0.0, 0
    local peak = 0.0
    for i, summary in ipairs(curve) do
        if summary.prosperousShare > peak then peak, peakGeneration = summary.prosperousShare, summary.generation end
        if i >= world.config.victoryStreak + 1 then
            local floor = 1.0
            for j = i - world.config.victoryStreak + 1, i do floor = math.min(floor, curve[j].prosperousShare) end
            bestFive = math.max(bestFive, floor)
        end
    end
    local foodOnly, craftOnly, both, neither = 0, 0, 0, 0
    for i, cell in ipairs(world.cells) do
        if S.IsHabitable(cell) then
            local m = world.metrics[i]
            local food = m.foodRatio >= world.config.prosperousFoodRatio
            local craft = m.craftPerCapita >= world.baselineCraft * world.config.prosperousCraftMultiplier
            if food and craft then both = both + cell.population
            elseif food then foodOnly = foodOnly + cell.population
            elseif craft then craftOnly = craftOnly + cell.population
            else neither = neither + cell.population end
        end
    end
    return { seed = world.seed, policy = policy, choiceSeed = choiceSeed, won = world.won,
        generation = world.generation, round = world.round, peak = peak, peakGeneration = peakGeneration,
        bestFive = bestFive, final = final, curve = curve, actions = world.actions,
        maxMigrationError = maxError, breakdown = { both = both / final.population,
            foodOnly = foodOnly / final.population, craftOnly = craftOnly / final.population,
            neither = neither / final.population } }
end

function W.Run(seed, policy, choiceSeed, plan, overrides)
    local world = S.New(seed, overrides)
    local rng = S.NewRandom(choiceSeed or 17)
    local curve = { world.history[1].summary }
    local maxError = 0.0
    for _ = 1, world.config.rounds do
        if policy ~= "baseline" then
            local action = plan and plan[world.round + 1] or W.Choose(world, policy, rng)
            assert(action, "missing action")
            local valid, reason = S.ApplyAction(world, action.action, action.x, action.y, action.withProtection)
            assert(valid, reason)
        end
        for _ = 1, world.config.generationsPerRound do
            local report = S.Tick(world)
            maxError = math.max(maxError, math.abs(report.migrationConservationError))
            assert(maxError < 1e-7, "migration conservation")
            for _, c in ipairs(world.cells) do
                assert(S.IsFinite(c.population) and c.population > 0, "invalid population")
                assert(S.IsFinite(c.landCapacity) and c.landCapacity > 0, "invalid capacity")
                assert(S.IsFinite(c.craft) and S.IsFinite(c.agriculture), "invalid technology")
                assert(c.foodShare >= world.config.foodShareMin and c.foodShare <= world.config.foodShareMax, "invalid food share")
            end
            curve[#curve + 1] = report.summary
            -- 批量测试仅释放已消费的逐格诊断；保留每世代统计与全部行动。
            -- 模拟不读取历史决定规则。另用正式 Replay 对完整记录复核。
            world.history = { report }
            if world.won then break end
        end
        if world.won then break end
    end
    local result = summarize(world, curve, policy, choiceSeed or 17, maxError)
    if overrides then result.config = world.config end
    return result
end

function W.Verify(result)
    local world = S.Replay(result.seed, result.actions, result.config)
    local valid, reason = S.VerifyReplay(world)
    assert(valid, reason)
    assert(world.won == result.won and world.generation == result.generation, "end state mismatch")
    assert(#world.history == #result.curve, "history count mismatch")
    for i, report in ipairs(world.history) do
        for key, value in pairs(report.summary) do
            assert(value == result.curve[i][key], "summary mismatch: " .. key)
        end
    end
    return true
end

-- 诊断实验：allExplore=true 是不可由玩家开局做到的反事实，不计入通关测试。
function W.Diagnose(seed, plan, allExplore)
    local world = S.New(seed)
    if allExplore then
        for _, cell in ipairs(world.cells) do
            if S.IsHabitable(cell) then cell.institution = world.config.exploreInstitution end
        end
        S.RefreshMetrics(world)
    end
    local curve = {}
    for round = 1, world.config.rounds do
        if plan then
            local a = plan[round]
            assert(S.ApplyAction(world, a.action, a.x, a.y, a.withProtection))
        end
        for _ = 1, world.config.generationsPerRound do
            local report = S.Tick(world)
            local population, shares = report.summary.population, { strict = 0, food99 = 0, food98 = 0, food95 = 0, craftOnly = 0 }
            for i, cell in ipairs(world.cells) do
                local m = world.metrics[i]
                if m.craftPerCapita >= world.baselineCraft * world.config.prosperousCraftMultiplier then
                    shares.craftOnly = shares.craftOnly + cell.population
                    if m.foodRatio >= 1 then shares.strict = shares.strict + cell.population end
                    if m.foodRatio >= 0.99 then shares.food99 = shares.food99 + cell.population end
                    if m.foodRatio >= 0.98 then shares.food98 = shares.food98 + cell.population end
                    if m.foodRatio >= 0.95 then shares.food95 = shares.food95 + cell.population end
                end
            end
            for key, value in pairs(shares) do shares[key] = value / population end
            curve[#curve + 1] = { generation = world.generation, summary = report.summary, thresholds = shares }
            world.history = { report }
            if world.won then return { allExplore = allExplore, curve = curve, won = true } end
        end
    end
    return { allExplore = allExplore, curve = curve, won = world.won }
end

return W
