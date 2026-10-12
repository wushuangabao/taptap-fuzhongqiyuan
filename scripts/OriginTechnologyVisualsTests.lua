local V = require("OriginTechnologyVisuals")
local S = require("OriginSimulation")
local Tests = {}

---@return table
local function Fixture()
    local cells = {}
    for y = 1, 3 do for x = 1, 3 do cells[#cells + 1] = {x = x, y = y} end end
    return {cells = cells, lastReport = {technologyFlows = {
        {from = 4, to = 5, kind = "agriculture", amount = 1, relativeGain = 0.001},
        {from = 5, to = 4, kind = "craft", amount = 1, relativeGain = 0.02},
        {from = 5, to = 6, kind = "agriculture", amount = 1, relativeGain = 0.1},
        {from = 2, to = 5, kind = "craft", amount = 1, relativeGain = 0.01},
        {from = 5, to = 8, kind = "craft", amount = 1, relativeGain = 0.03},
        {from = 1, to = 2, kind = "agriculture", amount = 0.000001, relativeGain = 0.00000001},
    }}}
end

local bounds = {x = 0, y = 0, cw = 40, ch = 34}
local viewport = {x = -20, y = -20, w = 200, h = 200}

function Tests.Run()
    local report = {passed = 0, failed = 0, ok = false, results = {}}
    local function test(name, run)
        local ok, err = pcall(run)
        report.results[#report.results + 1] = {name = name, passed = ok, error = not ok and tostring(err) or nil}
        if ok then report.passed = report.passed + 1 else report.failed = report.failed + 1 end
        print("[技术流] " .. (ok and "通过 " or "失败 ") .. name .. (ok and "" or tostring(err)))
    end
    test("全图保留远处传播、反向传播和微弱传播", function()
        local world = Fixture()
        local arrows = V.Arrows(world, bounds, viewport, true, 5)
        assert(#arrows == 6 and arrows[6].from == 1 and arrows[6].width > 0)
        assert(arrows[2].from == 5 and arrows[2].to == 4)
        assert(#V.Arrows(world, bounds, viewport, true, 1) == 6)
    end)
    test("局部保留四邻格所有传入和传出，隐藏其他边", function()
        local arrows = V.Arrows(Fixture(), bounds, viewport, false, 5)
        assert(#arrows == 5)
        local incoming, outgoing, neighbors = 0, 0, {}
        for _, arrow in ipairs(arrows) do
            if arrow.to == 5 then incoming = incoming + 1; neighbors[arrow.from] = true
            else assert(arrow.from == 5); outgoing = outgoing + 1; neighbors[arrow.to] = true end
        end
        assert(incoming == 2 and outgoing == 3)
        assert(neighbors[2] and neighbors[4] and neighbors[6] and neighbors[8])
        local corner = V.Arrows(Fixture(), bounds, viewport, false, 1)
        assert(#corner == 1 and corner[1].from == 1 and corner[1].to == 2)
    end)
    test("无传播不虚构箭头，非法或零流量不会绘制", function()
        assert(#V.Arrows({cells = {}}, bounds, viewport, true, 1) == 0)
        local world = Fixture()
        world.lastReport.technologyFlows = {
            {from = 1, to = 5, amount = 1, relativeGain = 0.1},
            {from = 1, to = 20, amount = 1, relativeGain = 0.1},
            {from = 1, to = 2, amount = 0, relativeGain = 0.1},
            {from = 1, to = 2, amount = 1, relativeGain = 0},
        }
        assert(#V.Arrows(world, bounds, viewport, true, 1) == 0)
    end)
    test("各缩放下传播增幅越大越粗，极强传播仍有上限", function()
        for _, size in ipairs({1, 8, 18, 34, 100, 300}) do
            local previous = 0
            for _, strength in ipairs({0.00000001, 0.0001, 0.001, 0.01, 0.1, 1, 100}) do
                local width = V.Width(strength, size)
                assert(width > previous and width <= math.min(9.0, size * 0.24))
                previous = width
            end
        end
        assert(V.Width(0.006, 34) > V.Width(0.00003, 34) * 6,
            "实际流量范围的强弱传播应有肉眼可辨的宽度差")
    end)
    test("两种技术和反向传播各有通道，箭头尖始终指向接收方", function()
        local world = Fixture()
        world.lastReport.technologyFlows = {}
        for _, pair in ipairs({{4, 5}, {5, 4}, {2, 5}, {5, 2}}) do
            for _, kind in ipairs({"agriculture", "craft"}) do
                world.lastReport.technologyFlows[#world.lastReport.technologyFlows + 1] = {
                    from = pair[1], to = pair[2], kind = kind, amount = 1, relativeGain = 0.01,
                }
            end
        end
        local arrows = V.Arrows(world, bounds, viewport, true, 5)
        for i, arrow in ipairs(arrows) do
            ---@type table
            local source = world.cells[arrow.from]
            ---@type table
            local target = world.cells[arrow.to]
            assert((arrow.tipX - arrow.startX) * (target.x - source.x)
                + (arrow.tipY - arrow.startY) * (target.y - source.y) > 0)
            if i % 2 == 0 then
                local other = arrows[i - 1]
                assert(math.abs(arrow.startX - other.startX) + math.abs(arrow.startY - other.startY) > 5)
            end
        end
        assert(arrows[1].startY > 51 and arrows[3].startY < 51)
        assert(arrows[5].startX < 60 and arrows[7].startX > 60)
    end)
    test("小格宽与全图视角仍绘制，裁剪保留穿过视口的箭头", function()
        local world = Fixture()
        assert(#V.Arrows(world, {x = 0, y = 0, cw = 8, ch = 7}, viewport, true, 5) == 6)
        local crossing = V.Arrows(world, bounds, {x = 38, y = 47, w = 4, h = 10}, true, 5)
        assert(#crossing >= 1, "源和目标在视口外但箭身穿过视口也应绘制")
        assert(#V.Arrows(world, bounds, {x = 500, y = 500, w = 20, h = 20}, true, 5) == 0)
    end)
    test("四个方向移动时保留完整箭尖和短箭身，拖尾不超过路径", function()
        local world = Fixture()
        world.lastReport.technologyFlows[#world.lastReport.technologyFlows + 1] = {
            from = 8, to = 5, kind = "agriculture", amount = 1, relativeGain = 0.01,
        }
        for _, size in ipairs({1, 8, 34, 300}) do
            for _, arrow in ipairs(V.Arrows(world, {x = 0, y = 0, cw = size, ch = size},
                {x = -10, y = -10, w = 2000, h = 2000}, true, 5)) do
                local timing = V.Timing(arrow)
                for _, phase in ipairs({0, 0.2, 0.5, 0.999}) do
                    local moving = assert(V.Moving(arrow, phase * timing.move))
                    assert(#moving.points == 7)
                    local function Along(p)
                        return (p[1] - arrow.startX) * arrow.ux + (p[2] - arrow.startY) * arrow.uy
                    end
                    local tip, base = Along(moving.points[4]), Along(moving.points[3])
                    assert(math.abs(tip - base - arrow.headLength) < 0.000001, "箭尖不能被动画裁掉")
                    assert(math.abs(base - Along(moving.points[1]) - arrow.shaftLength) < 0.000001)
                    for _, points in ipairs({moving.points, moving.tail and moving.tail.points or {}}) do
                        for _, p in ipairs(points) do
                            assert(Along(p) >= -0.000001 and Along(p) <= arrow.length + 0.000001)
                        end
                    end
                end
            end
        end
    end)
    test("透明渐变与箭头移动同速，消失期间保持原拖尾渐变宽度", function()
        for _, size in ipairs({8, 34, 140, 300}) do
            for _, arrow in ipairs(V.Arrows(Fixture(), {x=0,y=0,cw=size,ch=size},
                {x=-10,y=-10,w=2000,h=2000}, true, 5)) do
                local timing = V.Timing(arrow)
                local origin = 0
                local first = assert(V.Moving(arrow, origin + timing.move * 0.2))
                local next = assert(V.Moving(arrow, origin + timing.move * 0.4))
                local speed = ((next.tipX - first.tipX) * arrow.ux + (next.tipY - first.tipY) * arrow.uy) / (timing.move * 0.2)
                assert(math.abs(speed - timing.speed) < 0.000001)
                local arrived = assert(V.Moving(arrow, origin + timing.move))
                local function Along(x, y)
                    return (x - arrow.startX) * arrow.ux + (y - arrow.startY) * arrow.uy
                end
                local previousT, previousStart = timing.move, Along(arrived.gradient.x1, arrived.gradient.y1)
                for _, fraction in ipairs({0.1, 0.3, 0.5, 0.9}) do
                    local time = timing.move + timing.erase * fraction
                    local clearing = assert(V.Moving(arrow, origin + time))
                    assert(clearing.erasing and #clearing.points == 7)
                    assert(math.abs(clearing.tipX - arrow.tipX) + math.abs(clearing.tipY - arrow.tipY) < 0.000001)
                    local edge = clearing.gradient
                    local start, finish = Along(edge.x1, edge.y1), Along(edge.x2, edge.y2)
                    assert(math.abs((start - previousStart) / (time - previousT) - speed) < 0.000001,
                        "透明部分扩张必须与移动共享线速度")
                    assert(math.abs(finish - start - arrow.length * V.TrailFraction) < 0.000001,
                        "不能把消失的渐变压缩成窄边")
                    previousT, previousStart = time, start
                end
            end
        end
    end)
    test("整段动画共用可控时长，到期消失且不重播", function()
        local world = S.New(20261002)
        S.Tick(world)
        local arrow = assert(V.Arrows(world, bounds, viewport, true, 1)[1])
        local draws, rng = world.rng.draws, world.rng.state
        for _, duration in ipairs({3, 10, 20}) do
            local timing = V.Timing(arrow, duration)
            assert(math.abs(timing.move + timing.erase - duration) < 0.000001)
            assert(V.Moving(arrow, 0, duration))
            assert(V.Moving(arrow, duration - 0.001, duration).erasing)
            assert(V.Moving(arrow, duration, duration) == nil)
            assert(V.Moving(arrow, duration * 2, duration) == nil)
        end
        assert(world.rng.draws == draws and world.rng.state == rng)
    end)
    test("真实世代记录完整显示，切换显示不改变世界和随机数", function()
        local world = S.New(20261002)
        S.Tick(world)
        local before, generation, draws, rng = {}, world.generation, world.rng.draws, world.rng.state
        for i, cell in ipairs(world.cells) do
            before[i] = {}; for key, value in pairs(cell) do before[i][key] = value end
        end
        local fullBounds = {x = 0, y = 0, cw = 12, ch = 10}
        local fullViewport = {x = -20, y = -20, w = 1000, h = 1000}
        local arrows = V.Arrows(world, fullBounds, fullViewport, true, 180)
        assert(#arrows == #world.lastReport.technologyFlows and #arrows > 0)
        local count = 0
        for _, flow in ipairs(world.lastReport.technologyFlows) do
            if flow.from == 180 or flow.to == 180 then count = count + 1 end
        end
        assert(#V.Arrows(world, fullBounds, fullViewport, false, 180) == count)
        for i, cell in ipairs(world.cells) do for key, value in pairs(before[i]) do assert(cell[key] == value) end end
        assert(world.generation == generation and world.rng.draws == draws and world.rng.state == rng)
    end)
    report.ok = report.failed == 0
    return report
end

return Tests
