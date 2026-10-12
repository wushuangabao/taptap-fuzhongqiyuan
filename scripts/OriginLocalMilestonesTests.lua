-- 短回合夹具只隔离触发边界；正式参数另跑逐世代世界等价测试。
local S = require("OriginSimulation")
local M = require("OriginLocalMilestones")
local Tests = {}
local cases = {}
local function Test(name, run) cases[#cases + 1] = {name = name, run = run} end
local function Copy(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, item in pairs(value) do result[key] = Copy(item) end
    return result
end
local function Same(a, b)
    assert(type(a) == type(b), "类型不同")
    if type(a) ~= "table" then assert(a == b, "值不同"); return end
    for key, value in pairs(a) do Same(value, b[key]) end
    for key in pairs(b) do assert(a[key] ~= nil, "字段丢失") end
end
local function Fixture()
    local world = S.New(12345, {width = 6, height = 5, regionSize = 5, explorationAreas = 0,
        generationsPerRound = 2, protectionDuration = 2, naturalGrowthRate = 0,
        migrationRate = 0, replacementRate = 0, mobilizeAgricultureGrowth = 0, exploreAgricultureGrowth = 0, technologyDiffusion = 0,
        mobilizeImprovementProbability = 1, exploreImprovementProbability = 1}) -- 只隔离成功后的成果触发
    for _, cell in ipairs(world.cells) do
        cell.population, cell.landCapacity = 40, 40
        cell.agriculture, cell.foodShare, cell.craft = 3.9, 0.5, 2
        cell.institution = world.config.mobilizeInstitution
    end
    S.RefreshMetrics(world)
    return world
end
local function Apply(state, world, action, x, y, protect)
    x, y = x or 1, y or 1
    local before = Copy(world)
    local capture = M.Capture(world, action, x, y, protect)
    Same(before, world)
    assert(S.ApplyAction(world, action, x, y, protect))
    local after = Copy(world)
    assert(M.CommitAction(state, world, capture))
    Same(after, world)
    return capture
end
local function Tick(state, world)
    S.Tick(world)
    local snapshot = Copy(world)
    local emitted = M.Evaluate(state, world)
    Same(snapshot, world)
    return emitted
end

Test("缺粮改善只在轮末完成，真实干预前快照且不改变世界", function()
    local world, state = Fixture(), M.New()
    Apply(state, world, "agriculture")
    assert(not state.completed.food and #Tick(state, world) == 0)
    local events = Tick(state, world)
    assert(#events == 1 and events[1].kind == "food" and events[1].generation == 2)
    assert(#events[1].evidence.fedIndices == 25 and events[1].title == "温饱有了大幅改善")
    assert(#M.Evaluate(state, world) == 0 and #state.history == 1)
end)
Test("更多务农也可完成温饱改善", function()
    local world, state = Fixture(), M.New()
    Apply(state, world, "foodUp")
    Tick(state, world); Tick(state, world)
    assert(state.completed.food)
end)
Test("温饱文案按改善范围区分少许明显大幅且不显示格数", function()
    for _, case in ipairs({{1, "少许"}, {13, "明显"}, {25, "大幅"}}) do
        local world, state = Fixture(), M.New()
        Apply(state, world, "agriculture")
        local changed = 0
        for _, cell in ipairs(world.cells) do
            if cell.x <= 5 then
                changed = changed + 1
                if changed > case[1] then cell.agriculture = 2 end
            end
        end
        Tick(state, world); Tick(state, world)
        local event = assert(state.completed.food)
        assert(event.title == "温饱有了" .. case[2] .. "改善")
        assert(not event.title:find("格") and not event.detail:find("格"))
    end
end)
Test("中途温饱后再次缺粮不算A方案成功", function()
    local world, state = Fixture(), M.New()
    Apply(state, world, "agriculture"); Tick(state, world)
    for _, cell in ipairs(world.cells) do cell.agriculture = 2 end
    Tick(state, world)
    assert(not state.completed.food)
end)
Test("无干预的自然改善及非温饱行动不会冒领成功", function()
    for _, action in ipairs({"craft", "foodDown", "institution"}) do
        local world, state = Fixture(), M.New()
        Apply(state, world, action)
        for _, cell in ipairs(world.cells) do cell.agriculture = 8 end
        Tick(state, world); Tick(state, world)
        assert(not state.completed.food)
    end
    local world, state = Fixture(), M.New()
    for _, cell in ipairs(world.cells) do cell.agriculture = 8 end
    Tick(state, world); assert(#state.history == 0)
end)
Test("原本温饱与未实际改变的缺粮格不进入目标", function()
    local world, state = Fixture(), M.New()
    world.cells[1].agriculture = 6
    for _, cell in ipairs(world.cells) do cell.foodShare = world.config.foodShareMax end
    world.cells[2].agriculture = 1
    world.cells[3].foodShare = 0.5
    Apply(state, world, "foodUp")
    assert(not state.pending.hungry[1] and not state.pending.hungry[2] and state.pending.hungry[3])
end)
Test("探索存续只统计新建立的探索制度，半数阈值含等号", function()
    for _, survivors in ipairs({1, 2}) do
        local world, state = Fixture(), M.New()
        for i, cell in ipairs(world.cells) do if i > 4 then cell.institution = "explore" end end
        Apply(state, world, "institution")
        assert(state.pending.exploringTotal == 4)
        for i = survivors + 1, 4 do world.cells[i].institution = "mobilize" end
        Tick(state, world); Tick(state, world)
        assert((state.completed.exploration ~= nil) == (survivors == 2))
    end
end)
Test("探索中断后恢复不算连续存续，失败可在后续行动重试", function()
    local world, state = Fixture(), M.New()
    Apply(state, world, "institution")
    for _, cell in ipairs(world.cells) do cell.institution = "mobilize" end
    Tick(state, world)
    for _, cell in ipairs(world.cells) do cell.institution = "explore" end
    Tick(state, world); assert(not state.completed.exploration)
    for _, cell in ipairs(world.cells) do cell.institution = "mobilize" end
    Apply(state, world, "institution"); Tick(state, world); Tick(state, world)
    local event = state.completed.exploration --[[@as OriginLocalEvent?]]
    assert(event and event.round == 2)
end)
Test("真实技术向原选区外邻格传播才完成，来源和技术种类匹配", function()
    local world, state = Fixture(), M.New()
    world.config.technologyDiffusion = 0.05
    Apply(state, world, "craft")
    local events = Tick(state, world)
    assert(#events == 1 and events[1].kind == "technology")
    local flow = events[1].evidence.flow
    assert(flow.kind == "craft" and world.cells[flow.from].x == 5 and world.cells[flow.to].x == 6 and flow.amount > 0)
    Same(flow, world.history[2].technologyFlows[1])
    Tick(state, world); assert(#state.history == 1)
end)
Test("选区内学习、选区外自然强源、错误技术和零流量不算传播成果", function()
    local world, state = Fixture(), M.New()
    world.config.technologyDiffusion = 0.05
    for _, cell in ipairs(world.cells) do if cell.x == 6 then cell.craft = 10 end end
    Apply(state, world, "craft"); Tick(state, world)
    assert(not state.completed.technology)
    local pending = state.pending
    assert(pending)
    assert(not pending.indices[6] and pending.indices[5])
    -- 边界夹具单独检查过滤条件，正式端到端另核对真实报告。
    S.Tick(world)
    world.lastReport.technologyFlows = {{from = 1, to = 2, kind = "craft", amount = 1, relativeGain = 1},
        {from = 5, to = 6, kind = "agriculture", amount = 1, relativeGain = 1},
        {from = 5, to = 6, kind = "craft", amount = 0, relativeGain = 0},
        {from = 1, to = 6, kind = "craft", amount = 1, relativeGain = 1}}
    M.Evaluate(state, world); assert(not state.completed.technology)
end)
Test("遗漏更新会补读真实历史，提前终局不会把短轮算成整轮", function()
    local world, state = Fixture(), M.New()
    Apply(state, world, "institution")
    S.Tick(world); S.Tick(world)
    assert(#M.Evaluate(state, world) == 1 and state.completed.exploration)
    local early, progress = Fixture(), M.New()
    Apply(progress, early, "institution"); Tick(progress, early)
    early.won = true
    assert(#M.Evaluate(progress, early) == 0 and not progress.completed.exploration)
end)
Test("无效失败重复及错配行动不能登记，跨世界不能复用", function()
    local world, state = Fixture(), M.New()
    assert(not M.Capture(world, "wrong", 1, 1) and not M.Capture(world, "craft", 3, 1))
    local candidate = M.Capture(world, "agriculture", 1, 1)
    assert(not M.CommitAction(state, world, candidate))
    assert(S.ApplyAction(world, "craft", 1, 1))
    assert(not M.CommitAction(state, world, candidate))
    local second, tracking = Fixture(), M.New()
    local capture = Apply(tracking, second, "agriculture")
    assert(not M.CommitAction(tracking, second, capture))
    local other = Fixture()
    local otherCapture = M.Capture(other, "craft", 1, 1)
    assert(S.ApplyAction(other, "craft", 1, 1))
    assert(not M.CommitAction(tracking, other, otherCapture))
end)
Test("已完成历史不因衰退丢失也不在重复行动奖励，重开独立", function()
    local world, state = Fixture(), M.New()
    Apply(state, world, "agriculture"); Tick(state, world); Tick(state, world)
    local history = Copy(state.history)
    for _, cell in ipairs(world.cells) do cell.agriculture = 3.9 end
    Apply(state, world, "agriculture"); Tick(state, world); assert(#Tick(state, world) == 0)
    Same(history, state.history)
    local fresh, reset = Fixture(), M.New()
    assert(#reset.history == 0 and not reset.completed.food and not reset.pending)
    Apply(reset, fresh, "agriculture"); Tick(reset, fresh); Tick(reset, fresh)
    assert(reset.completed.food)
end)
Test("正式世界逐世代等价，随机流资源行动次数和胜利条件无副作用", function()
    for _, seed in ipairs({20261002, 104730, 209459}) do
        local observed, control, state = S.New(seed), S.New(seed), M.New()
        for _, action in ipairs({"craft", "agriculture", "foodUp", "institution", "protect"}) do
            Apply(state, observed, action, 10, 6)
            assert(S.ApplyAction(control, action, 10, 6))
            Same(observed, control)
            for _ = 1, observed.config.generationsPerRound do
                Tick(state, observed); S.Tick(control); Same(observed, control)
            end
        end
        assert(observed.config.victoryShare == 0.8 and observed.config.victoryStreak == 5)
    end
end)

function Tests.Run()
    local result = {passed = 0, failed = 0, total = #cases, results = {}, ok = false}
    for _, case in ipairs(cases) do
        local ok, err = pcall(case.run)
        result.results[#result.results + 1] = {name = case.name, passed = ok, error = not ok and tostring(err) or nil}
        if ok then result.passed = result.passed + 1 else result.failed = result.failed + 1 end
        print("[局部成果测试] " .. (ok and "通过 " or "失败 ") .. case.name .. (ok and "" or "：" .. tostring(err)))
    end
    result.ok = result.failed == 0
    return result
end
return Tests
