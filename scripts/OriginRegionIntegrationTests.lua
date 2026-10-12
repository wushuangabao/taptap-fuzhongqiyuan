-- 特色地区与正式模拟/地图标注的集成契约。
local S = require("OriginSimulation")
local Config = require("OriginConfig")
local Layout = require("OriginRegionLayout")
local Camera = require("OriginCamera")
local Tests = {}

local function same(a, b)
    assert(type(a) == type(b), "类型不同")
    if type(a) ~= "table" then assert(a == b, "值不同"); return end
    for key, value in pairs(a) do same(value, b[key]) end
    for key in pairs(b) do assert(a[key] ~= nil, "缺少字段") end
end

function Tests.Run()
    local report = {passed = 0, failed = 0, results = {}, ok = false}
    local function test(name, fn)
        local ok, err = pcall(fn)
        report.results[#report.results + 1] = {name = name, passed = ok, error = not ok and tostring(err) or nil}
        if ok then report.passed = report.passed + 1 else report.failed = report.failed + 1 end
        print("[地区集成] " .. (ok and "通过 " or "失败 ") .. name .. (ok and "" or (": " .. tostring(err))))
    end
    test("开局地区与格子对应且可稳定重建", function()
        local a, b = S.New(), S.New()
        assert(#a.regions == 4 and #a.cellRegionIds == #a.cells)
        same(a.regions, b.regions); same(a.cellRegionIds, b.cellRegionIds); same(a.cells, b.cells)
        for _, region in ipairs(a.regions) do
            for _, index in ipairs(region.indices) do assert(a.cellRegionIds[index] == region.id) end
        end
    end)
    test("生成地区不额外消耗模拟随机流", function()
        local world = S.New(15, {explorationAreas = 0})
        local rng = S.NewRandom(15)
        for _ = 1, #world.cells * 5 do S.Random(rng) end
        same(world.rng, rng)
    end)
    test("地区是开局特征而非后续永久经济加成", function()
        local a, b = S.New(55), S.New(55)
        b.regions[1].kind = "craft"
        b.regions[1].name = "改名不改模拟"
        for i = 1, #b.cellRegionIds do b.cellRegionIds[i] = 1 end
        assert(S.ApplyAction(a, "agriculture", 1, 1)); assert(S.ApplyAction(b, "agriculture", 1, 1))
        for _ = 1, Config.generationsPerRound do S.Tick(a); S.Tick(b) end
        same(a.cells, b.cells); same(a.history, b.history); same(a.rng, b.rng)
    end)
    test("跨区干预与整轮重放保留完整地区身份", function()
        local world = S.New(20261002)
        for _, action in ipairs({"craft", "agriculture", "institution"}) do
            assert(S.ApplyAction(world, action, 10, 6))
            for _ = 1, Config.generationsPerRound do S.Tick(world) end
        end
        local valid, reason = S.VerifyReplay(world)
        assert(valid, reason)
        world.regions[1].name = "错误的地区"
        local tampered, detail = S.VerifyReplay(world)
        assert(not tampered and detail == "geography_mismatch")
    end)
    test("旧模型版本的行动记录不能悄悄套到新地图", function()
        local ok = pcall(S.Replay, 20261002, {{action = "craft", x = 1, y = 1, modelVersion = "origin-1.1.0"}})
        assert(not ok)
        local forgedConfig = {modelVersion = "origin-1.1.0"}
        assert(not pcall(S.Replay, 20261002,
            {{action = "craft", x = 1, y = 1, modelVersion = "origin-1.1.0"}}, forgedConfig))
    end)
    test("各倍率标注在视口内且互不遮挡，不修改世界", function()
        for _, seed in ipairs({1, 104730, 20261002}) do
            local world = S.New(seed)
            local rngState, draws = world.rng.state, world.rng.draws
            for _, viewport in ipairs({{x = 0, y = 0, w = 330, h = 180}, {x = 20, y = 30, w = 860, h = 530}}) do
                for _, zoom in ipairs({1, 2.5, 6}) do
                    local camera = Camera.New()
                    camera.zoom = zoom
                    local geometry = Camera.Geometry(camera, viewport, world.width, world.height)
                    local labels = Layout.Labels(world, geometry, viewport, 2)
                    assert(#labels <= 4)
                    for i, label in ipairs(labels) do
                        assert(label.x >= viewport.x and label.y >= viewport.y)
                        assert(label.x + label.w <= viewport.x + viewport.w and label.y + label.h <= viewport.y + viewport.h)
                        for j = i + 1, #labels do
                            local other = labels[j]
                            assert(label.x + label.w <= other.x or other.x + other.w <= label.x
                                or label.y + label.h <= other.y or other.y + other.h <= label.y)
                        end
                    end
                end
            end
            assert(world.rng.state == rngState and world.rng.draws == draws and world.generation == 0)
        end
    end)
    test("名称重叠时保留所选地区，屏外名称不吸附错位", function()
        local world = S.New()
        for _, region in ipairs(world.regions) do region.anchorX, region.anchorY = 12, 8 end
        local view = {x = 0, y = 0, w = 600, h = 400}
        local geometry = {x = 0, y = 0, cw = 20, ch = 20}
        local labels = Layout.Labels(world, geometry, view, 3)
        assert(#labels == 1 and labels[1].region.id == 3)
        geometry.x = -1000
        assert(#Layout.Labels(world, geometry, view, 3) == 0)
    end)
    report.ok = report.failed == 0
    return report
end

return Tests
