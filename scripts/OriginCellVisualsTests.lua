-- 验证真实经济变化能驱动图形，并且图形只读取数据、在各缩放下保持布局。
local V = require("OriginCellVisuals")
local S = require("OriginSimulation")
local Tests = {}

local function state(world, index)
    local cell = world.cells[index]
    local metric = S.Metrics(cell, world.config)
    return V.State(cell.population, metric.foodRatio, metric.craftPerCapita, world.baselineCraft)
end

function Tests.Run()
    local report = {passed = 0, failed = 0, ok = false, results = {}}
    local function test(name, run)
        local ok, err = pcall(run)
        report.results[#report.results + 1] = {name = name, passed = ok, error = not ok and tostring(err) or nil}
        if ok then report.passed = report.passed + 1 else report.failed = report.failed + 1 end
        print("[地块信息图] " .. (ok and "通过 " or "失败 ") .. name .. (ok and "" or tostring(err)))
    end
    test("缺粮保留暖色，温饱临界为黄，盈余渐绿；数量刻度不变", function()
        local lastCount, lastGreen = 0, 0
        for _, food in ipairs({0, 0.4, 0.6, 0.8, 0.9, 0.96, 0.99, 0.999999, 1, 1.01, 1.02, 1.05, 1.2, 1.5, 10}) do
            local value = V.State(30, food, 0.5, 0.5)
            assert(value.foodBlocks >= lastCount and value.foodBlocks <= 6)
            assert(value.foodColor[2] / value.foodColor[1] >= lastGreen)
            if food < 1 then
                assert(value.foodColor[1] - value.foodColor[2] >= 50, "缺粮不应呈绿色")
            elseif food >= 1.02 then
                assert(value.foodColor[2] > value.foodColor[1], "盈余应向绿色过渡")
            end
            lastCount, lastGreen = value.foodBlocks, value.foodColor[2] / value.foodColor[1]
        end
        local fed = V.State(30, 1, 0.5, 0.5)
        assert(fed.foodColor[1] == 225 and fed.foodColor[2] == 174 and fed.foodColor[3] == 65)
        assert(fed.foodBlocks == 4)
        assert(V.State(30, 0, 1, 1).foodBlocks == 0)
        assert(V.State(30, -1, 1, 1).foodBlocks == 0)
        for i, threshold in ipairs({0.01, 0.33, 0.66, 1.0, 1.25, 1.5}) do
            assert(V.State(30, threshold - 1e-5, 1, 1).foodBlocks == i - 1)
            assert(V.State(30, threshold, 1, 1).foodBlocks == i)
            assert(V.State(30, threshold + 1e-5, 1, 1).foodBlocks == i)
        end
        local capped = V.State(95, 1e6, 3, 1)
        assert(capped.foodBlocks == 6 and capped.houses == 6 and capped.roses == 6)
    end)
    test("颜色跨越温饱线连续，近处变化比远处陡峭", function()
        local function distance(a, b)
            local ca, cb = V.State(30, a, 1, 1).foodColor, V.State(30, b, 1, 1).foodColor
            local difference = 0
            for i = 1, 3 do difference = difference + math.abs(ca[i] - cb[i]) end
            return difference
        end
        assert(distance(1 - 1e-6, 1 + 1e-6) < 0.02, "临界处不应跳色")
        local near = distance(0.99, 1.01)
        assert(near > 60, "温饱附近变化不够明显")
        assert(near > 10 * distance(0.8, 0.82) and near > 10 * distance(1.18, 1.2), "远处应变化较缓")
    end)
    test("劳动转向农业会提高农业标识并减少手工业玫瑰", function()
        local world = S.New(1, {width = 1, height = 1, explorationAreas = 0})
        local c = world.cells[1]
        c.population, c.landCapacity, c.agriculture, c.craft = 20, 20, 4, 4
        world.baselineCraft = 1
        c.foodShare = 0.4
        local before = state(world, 1)
        c.foodShare = 0.8
        local after = state(world, 1)
        assert(after.foodBlocks > before.foodBlocks and after.roses < before.roses)
        assert(after.houses == before.houses)
    end)
    test("相同总产出不会掩盖人口增长造成的人均差异", function()
        local low = V.State(15, 1.5, 2, 1)
        local high = V.State(60, 1.5 / 4, 2 / 4, 1)
        assert(high.houses > low.houses and high.roses < low.roses and high.foodBlocks < low.foodBlocks)
        assert(V.State(90, 1, 1, 1).houses == 6)
        assert(V.State(1e6, 1e6, 1e6, 1).houses == 6)
    end)
    test("标识反映当前值，衰退可下降且读取不改变模拟", function()
        local world = S.New()
        local snapshot = {}
        for i, cell in ipairs(world.cells) do
            snapshot[i] = {}
            for key, value in pairs(cell) do snapshot[i][key] = value end
        end
        local draws, rng = world.rng.draws, world.rng.state
        for _ = 1, 3 do for i in ipairs(world.cells) do state(world, i) end end
        for i, cell in ipairs(world.cells) do
            for key, value in pairs(snapshot[i]) do assert(cell[key] == value) end
        end
        assert(world.rng.draws == draws and world.rng.state == rng)
        local developed, declined = V.State(90, 2, 3, 1), V.State(15, 0.5, 0.25, 1)
        assert(declined.houses < developed.houses and declined.roses < developed.roses
            and declined.foodBlocks < developed.foodBlocks)
    end)
    test("六块长方形、六栋住宅和六朵玫瑰全部在格内且任意两项均不重叠", function()
        for _, width in ipairs({22, 30, 42, 60, 100, 288}) do
            local height = width / 1.18
            local layout = V.Layout(width, height)
            local boxes = {}
            assert(#layout.food == 6 and #layout.houses == 6 and #layout.roses == 6)
            for _, block in ipairs(layout.food) do
                assert(block.width == width * 0.25 and block.width > block.height)
                boxes[#boxes + 1] = {block.x, block.y, block.x + block.width, block.y + block.height}
            end
            for _, house in ipairs(layout.houses) do
                -- 与实际房屋绘制一致，包含突出墙体的屋檐和屋顶。
                boxes[#boxes + 1] = {house.x - house.size * 0.025, house.y - house.size * 0.21 * 0.65,
                    house.x + house.size * 0.245, house.y + house.size * 0.21}
                assert(house.y - house.size * 0.21 * 0.65 > height * 0.18)
            end
            for _, rose in ipairs(layout.roses) do
                -- 包含叶子、最外花瓣和茎的半线宽，使用保守外接矩形。
                boxes[#boxes + 1] = {rose.x - rose.size * 1.5, rose.y - rose.size * 1.15,
                    rose.x + rose.size * 1.2, rose.y + rose.size * 2.36}
            end
            for i, a in ipairs(boxes) do
                assert(a[1] > 0 and a[2] > 0 and a[3] < width and a[4] < height, "标识越界")
                for j = i + 1, #boxes do
                    local b = boxes[j]
                    local gap = math.max(b[1] - a[3], a[1] - b[3], b[2] - a[4], a[2] - b[4])
                    assert(gap >= height * 0.02, "满档标识重叠或间距不足")
                end
            end
        end
    end)
    report.ok = report.failed == 0
    return report
end
return Tests
