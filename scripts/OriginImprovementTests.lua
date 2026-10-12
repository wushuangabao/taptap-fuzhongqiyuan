-- 概率改良专项：边界夹具与正式参数重放分开，require 不执行测试。
local S = require("OriginSimulation")
local R = require("OriginRecommendation")
local M = require("OriginLocalMilestones")
local Tests = {}

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

local function Fixture(overrides)
    local cfg = {width = 1, height = 1, regionSize = 1, explorationAreas = 0, terrainEnabled = false}
    for key, value in pairs(overrides or {}) do cfg[key] = value end
    local world = S.New(12345, cfg)
    for _, cell in ipairs(world.cells) do
        cell.population, cell.landCapacity, cell.agriculture, cell.craft, cell.foodShare = 40, 40, 4, 2, 0.5
        cell.institution = "mobilize"
    end
    world.baselineCraft = 0.5
    S.RefreshMetrics(world)
    return world
end

function Tests.Run()
    local report = {passed = 0, failed = 0, results = {}, ok = false}
    local function Test(name, run)
        local ok, err = pcall(run)
        report.results[#report.results + 1] = {name = name, passed = ok, error = not ok and tostring(err) or nil}
        if ok then report.passed = report.passed + 1 else report.failed = report.failed + 1 end
    end
    Test("正式参数10%与30%，非法概率被拒绝", function()
        local cfg = S.ResolveConfig()
        assert(cfg.mobilizeImprovementProbability == 0.1 and cfg.exploreImprovementProbability == 0.3)
        for _, key in ipairs({"mobilizeImprovementProbability", "exploreImprovementProbability"}) do
            for _, value in ipairs({-0.01, 1.01, math.huge, 0/0, "0.2"}) do
                assert(not pcall(S.ResolveConfig, {[key] = value}))
            end
        end
    end)
    Test("同一抽签值受当前制度影响，两种改良都有成功与失败", function()
        for _, action in ipairs({"agriculture", "craft"}) do
            for _, institution in ipairs({"mobilize", "explore"}) do
                -- 首次抽签约为0.000008、0.196、0.783，覆盖两侧与制度分歧区间。
                for _, seed in ipairs({1, 25000, 100000}) do
                    local world = Fixture()
                    local cell = world.cells[1]
                    cell.institution, world.rng = institution, S.NewRandom(seed)
                    local before, state = Copy(cell), world.rng.state
                    assert(S.ApplyAction(world, action, 1, 1))
                    local record, expected = world.actions[1], seed == 1 or (seed == 25000 and institution == "explore")
                    local outcome = record.improvements[1]
                    assert(outcome.succeeded == expected and outcome.institution == institution)
                    assert(outcome.probability == (institution == "explore" and 0.3 or 0.1))
                    assert(record.rngState == state and record.rngDraws == 0 and record.rngDrawsAfter == 1)
                    local key = action == "agriculture" and "agricultureActionMultiplier" or "craftActionMultiplier"
                    before[action] = before[action] * (expected and world.config[key] or 1)
                    Same(before, cell)
                    assert(world.round == 1 and world.generation == 0 and #world.actions == 1)
                end
            end
        end
    end)
    Test("0%和100%边界各抽一次，改良不使用保护且消耗一轮", function()
        for _, probability in ipairs({0, 1}) do
            for _, action in ipairs({"agriculture", "craft"}) do
                local world = Fixture({mobilizeImprovementProbability = probability, exploreImprovementProbability = probability})
                local draws = world.rng.draws
                assert(S.ApplyAction(world, action, 1, 1))
                assert(world.actions[1].improvements[1].succeeded == (probability == 1))
                assert(world.rng.draws == draws + 1 and world.protectionLeft == 3 and world.cells[1].protectionTicks == 0)
                local before = Copy(world)
                assert(not S.ApplyAction(world, action, 1, 1)); Same(before, world)
                for _ = 1, 5 do S.Tick(world) end
                assert(world.generation == 5 and world.cells[1].protectionTicks == 0)
                assert(S.ValidateAction(world, action, 1, 1))
            end
        end
    end)
    Test("非法操作和只读推荐不消耗随机数或保护", function()
        local world = Fixture()
        local before = Copy(world)
        for _ = 1, 10 do
            R.Choose(world, 1, 1)
            S.ValidateAction(world, "craft", 1, 1, true)
            assert(not S.ApplyAction(world, "craft", 2, 1, true))
            assert(not S.ApplyAction(world, "protect", 2, 1))
        end
        Same(before, world)
        world.protectionLeft = 0; before = Copy(world)
        assert(not S.ApplyAction(world, "protect", 1, 1)); Same(before, world)
    end)
    Test("确定性行动不抽改良签，制度改变后使用新制度概率", function()
        for _, action in ipairs({"foodUp", "foodDown", "institution", "protect", "skip"}) do
            local world = Fixture()
            local state, draws = world.rng.state, world.rng.draws
            assert(S.ApplyAction(world, action, 1, 1))
            assert(world.rng.state == state and world.rng.draws == draws and #world.actions[1].improvements == 0)
            if action == "institution" then
                for _ = 1, 5 do S.Tick(world) end
                assert(S.ApplyAction(world, "craft", 1, 1))
                assert(world.actions[2].improvements[1].probability == 0.3)
            end
        end
    end)
    Test("多格实验夹具按固定顺序独立抽签，不附带保护", function()
        local world = Fixture({width = 2, height = 2, regionSize = 2})
        world.cells[2].institution, world.cells[4].institution = "explore", "explore"
        local random = Copy(world.rng)
        assert(S.ApplyAction(world, "craft", 1, 1))
        for i, cell in ipairs(world.cells) do
            local roll = S.Random(random)
            local outcome = world.actions[1].improvements[i]
            assert(outcome.index == i and outcome.roll == roll)
            assert(cell.craft == 2 * (roll < S.ImprovementProbability(cell, world.config) and 1.15 or 1))
            assert(cell.protectionTicks == 0)
        end
        Same(random, world.rng)
    end)
    Test("失败不计为玩家带来的农业或技术成果", function()
        for _, action in ipairs({"agriculture", "craft"}) do
            local world, state = Fixture({mobilizeImprovementProbability = 0}), M.New()
            world.cells[1].agriculture = 3.9
            local candidate = M.Capture(world, action, 1, 1)
            assert(S.ApplyAction(world, action, 1, 1))
            assert(M.CommitAction(state, world, candidate))
            assert(next(state.pending.technology) == nil and next(state.pending.hungry) == nil)
            for _ = 1, 5 do S.Tick(world); M.Evaluate(state, world) end
            assert(#state.history == 0)
        end
    end)
    Test("两种制度长期自然工艺增长不同，改革不立即赠送技术", function()
        -- 关闭邻格学习，仅隔离制度本身的100世代复利。
        local world = Fixture({width = 2, technologyDiffusion = 0})
        local before, draws = world.cells[2].craft, world.rng.draws
        assert(S.ApplyAction(world, "institution", 2, 1))
        assert(world.cells[2].craft == before and world.cells[2].institution == "explore")
        for _ = 1, 100 do S.GrowTechnology(world) end
        assert(math.abs(world.cells[1].craft - before * 1.002 ^ 100) < 1e-10)
        assert(math.abs(world.cells[2].craft - before * 1.015 ^ 100) < 1e-10)
        assert(world.rng.draws == draws)
        assert(S.ImprovementProbability(world.cells[1], world.config) == 0.1)
        assert(S.ImprovementProbability(world.cells[2], world.config) == 0.3)
    end)
    Test("推荐按预期收益改变，不把高增幅视为必然", function()
        local world = Fixture({mobilizeImprovementProbability = 1})
        assert(R.Choose(world, 1, 1) == "craft")
        world.config.mobilizeImprovementProbability = 0.1
        assert(R.Choose(world, 1, 1) == "institution")
    end)
    Test("正式参数多轮完整重放并拒绝篡改结果与旧版本", function()
        local world = S.New()
        for round = 1, 8 do
            assert(S.ApplyAction(world, round == 1 and "protect" or (round % 2 == 0 and "agriculture" or "craft"), 12, 8))
            for _ = 1, 5 do S.Tick(world) end
        end
        assert(S.VerifyReplay(world))
        for _, field in ipairs({"probability", "roll", "index", "institution", "succeeded"}) do
            local actions = Copy(world.actions)
            local outcome = actions[2].improvements[1]
            if field == "succeeded" then outcome[field] = not outcome[field]
            elseif field == "institution" then outcome[field] = "tampered"
            else outcome[field] = outcome[field] + 0.01 end
            assert(not pcall(S.Replay, world.seed, actions))
        end
        for _, field in ipairs({"rngState", "rngDraws", "rngStateAfter", "rngDrawsAfter"}) do
            local actions = Copy(world.actions)
            actions[1][field] = actions[1][field] + 1
            assert(not pcall(S.Replay, world.seed, actions))
        end
        local actions = Copy(world.actions)
        actions[1].modelVersion = "origin-1.9.4"
        assert(not pcall(S.Replay, world.seed, actions))
    end)
    report.ok, report.total = report.failed == 0, #report.results
    return report
end

return Tests
