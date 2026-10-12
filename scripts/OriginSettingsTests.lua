local T = {}
function T.Run()
    local S, Settings = require("OriginSimulation"), require("OriginSettings")
    local report = {passed = 0, failed = 0, results = {}, ok = false}
    local function Test(name, fn)
        local ok, err = pcall(fn)
        report.results[#report.results + 1] = {name = name, passed = ok, error = not ok and tostring(err) or nil}
        report[ok and "passed" or "failed"] = report[ok and "passed" or "failed"] + 1
    end
    local function Near(a, b) assert(math.abs(a - b) < 1e-10, tostring(a) .. " ~= " .. tostring(b)) end
    Test("所有字段都有说明、有效范围，默认值可无损往返", function()
        local config = S.ResolveConfig()
        local draft = Settings.New(config, true)
        assert(#Settings.fields == 24)
        for _, f in ipairs(Settings.fields) do
            assert(#f.tip > 20 and f.min <= f.max)
            assert(Settings.Set(draft, f.key, Settings.Display(config, f.key)))
            Near(draft.config[f.key], config[f.key])
        end
        assert(Settings.Validate(draft))
    end)
    Test("只读与编辑草稿均不改写世界或默认值", function()
        local world = S.New(15)
        local rng = world.rng.state
        local readonly = Settings.New(world.config, false)
        assert(not Settings.Set(readonly, "naturalGrowthRate", "10"))
        Settings.Reset(readonly)
        local editable = Settings.New(world.config, true)
        assert(Settings.Set(editable, "naturalGrowthRate", "10"))
        assert(world.config.naturalGrowthRate == .5 and require("OriginConfig").naturalGrowthRate == .5)
        assert(world.rng.state == rng and world.generation == 0)
    end)
    Test("非法输入阻止保存，保留上一有效曲线值", function()
        local draft = Settings.New(S.ResolveConfig(), true)
        for _, text in ipairs({"", "abc", "nan", "1e999", "-1", "100"}) do
            assert(not Settings.Set(draft, "naturalGrowthRate", text))
            assert(not Settings.Validate(draft))
            assert(draft.config.naturalGrowthRate == .5)
        end
        assert(Settings.Set(draft, "naturalGrowthRate", "25.125"))
        assert(Settings.Validate(draft))
        Near(draft.config.naturalGrowthRate, .25125)
    end)
    Test("每项编辑上下界均能进入正式配置，越界被拒绝", function()
        for _, f in ipairs(Settings.fields) do
            for _, boundary in ipairs({f.min, f.max}) do
                local draft = Settings.New(S.ResolveConfig(), true)
                assert(Settings.Set(draft, f.key, tostring(boundary)), f.key)
                assert(Settings.Validate(draft), f.key)
                assert(not Settings.Set(draft, f.key, tostring(f.max + 1)))
                assert(not Settings.Set(draft, f.key, tostring(f.min - 1)))
            end
        end
    end)
    Test("人口曲线与结算一致，温饱线、零系数和上下限正确", function()
        local world = S.New(15, {naturalGrowthSlope = 3.25, naturalGrowthRate = .75})
        local before, ratios = {}, {}
        for i, cell in ipairs(world.cells) do before[i] = cell.population; ratios[i] = S.Metrics(cell, world.config).foodRatio end
        local deltas = S.NaturalGrowth(world)
        for i in ipairs(world.cells) do Near(deltas[i], before[i] * S.PopulationChangeRate(ratios[i], world.config)) end
        assert(S.PopulationChangeRate(1, world.config) == 0)
        Near(S.PopulationChangeRate(.5, world.config), -S.PopulationChangeRate(1.5, world.config))
        assert(S.PopulationChangeRate(100, world.config) <= .75)
        world.config.naturalGrowthSlope = 0
        assert(S.PopulationChangeRate(0, world.config) == 0)
    end)
    Test("两种制度独立农业增长，工艺和学习仍按实际参数", function()
        local world = S.New(15, {mobilizeAgricultureGrowth = .1, exploreAgricultureGrowth = .2, technologyDiffusion = 0})
        local before = {}
        for i, cell in ipairs(world.cells) do before[i] = cell.agriculture end
        S.GrowTechnology(world)
        local counts = {mobilize = 0, explore = 0}
        for i, cell in ipairs(world.cells) do
            if S.IsHabitable(cell) then
                counts[cell.institution] = counts[cell.institution] + 1
                Near(cell.agriculture, before[i] * (cell.institution == "explore" and 1.2 or 1.1))
            end
        end
        assert(counts.mobilize > 0 and counts.explore > 0)
    end)
    Test("自定义改良概率与增幅生效，整局配置支持重放", function()
        local draft = Settings.New(S.ResolveConfig(), true)
        for key, text in pairs({mobilizeImprovementProbability = "100", exploreImprovementProbability = "100",
            craftActionMultiplier = "27", naturalGrowthSlope = "3", naturalGrowthRate = "25",
            migrationRate = "15", exploreAgricultureGrowth = "1"}) do assert(Settings.Set(draft, key, text)) end
        local config = assert(Settings.Validate(draft))
        local world = S.New(15, config)
        local cell = world.cells[1]
        assert(S.IsHabitable(cell))
        local craft = cell.craft
        assert(S.ApplyAction(world, "craft", 1, 1))
        Near(cell.craft, craft * 1.27)
        for _ = 1, config.generationsPerRound do S.Tick(world) end
        local ok, reason = S.VerifyReplay(world)
        assert(ok, reason)
    end)
    Test("重置覆盖全部可编辑项，不重置种子等其他配置", function()
        local config = S.ResolveConfig({defaultSeed = 42})
        local draft = Settings.New(config, true)
        for _, f in ipairs(Settings.fields) do Settings.Set(draft, f.key, tostring(f.max)) end
        Settings.Set(draft, "naturalGrowthRate", "invalid")
        Settings.Reset(draft)
        for _, f in ipairs(Settings.fields) do assert(draft.config[f.key] == require("OriginConfig")[f.key]) end
        assert(draft.config.defaultSeed == 42 and not Settings.Error(draft))
    end)
    report.ok = report.failed == 0
    return report
end
return T
