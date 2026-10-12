-- 地貌底图的连片、覆盖范围、形态区分与只读性回归；不代替真实视觉验收。
local Backdrop = require("OriginTerrainBackdrop")
local Simulation = require("OriginSimulation")
local Tests = {}

local function Fixture(rows)
    local world = Simulation.New(1, {width = #rows[1], height = #rows, explorationAreas = 0})
    local kinds = {p = "plain", h = "hill", m = "mountain"}
    for y, row in ipairs(rows) do
        for x = 1, #row do
            local cell = world.cells[(y - 1) * #row + x]
            cell.terrainKind, cell.elevation = kinds[row:sub(x, x)], 0.8
        end
    end
    return world
end

function Tests.Run()
    local report = {passed = 0, failed = 0, ok = false, results = {}}
    local function Test(name, fn)
        local ok, err = pcall(fn)
        report.results[#report.results + 1] = {name = name, passed = ok, error = not ok and tostring(err) or nil}
        if ok then report.passed = report.passed + 1 else report.failed = report.failed + 1 end
    end
    Test("平原不产生地貌底板", function()
        local geometry = Backdrop.Geometry(Fixture({"ppp", "ppp"}))
        assert(#geometry.ranges == 0 and geometry.groups == 0)
    end)
    Test("横向和纵向相邻地形连片，山地与丘陵分别成组", function()
        local geometry = Backdrop.Geometry(Fixture({"hhmm", "hhmm"}))
        assert(geometry.groups == 2 and #geometry.ranges == 4)
        assert(geometry.groupIds[1] == geometry.groupIds[6])
        assert(geometry.groupIds[3] == geometry.groupIds[8])
        assert(geometry.groupIds[1] ~= geometry.groupIds[3])
        for _, range in ipairs(geometry.ranges) do assert(range.right - range.left == 1) end
    end)
    Test("平原和仅对角接触不连接山体", function()
        assert(Backdrop.Geometry(Fixture({"mpm", "mpm"})).groups == 2)
        assert(Backdrop.Geometry(Fixture({"mp", "pm"})).groups == 2)
    end)
    Test("环形山体保留中间的平原孔洞", function()
        local geometry = Backdrop.Geometry(Fixture({"mmm", "mpm", "mmm"}))
        assert(geometry.groups == 1 and geometry.groupIds[5] == nil)
        for _, range in ipairs(geometry.ranges) do
            assert(range.row ~= 2 or range.left > 2 or range.right < 2)
        end
    end)
    Test("山峰高峻而土坡低缓，山脊跨格连续且不越过真实地形范围", function()
        local geometry = Backdrop.Geometry(Fixture({"mmmmhhhhh"}))
        for _, range in ipairs(geometry.ranges) do
            local cursor = range.left - 1
            for _, peak in ipairs(range.peaks) do
                assert(math.abs(peak.x - cursor) < 1e-9 and peak.width > 0)
                assert(peak.height >= (range.kind == "mountain" and 0.67 or 0.25))
                assert(peak.height <= (range.kind == "mountain" and 0.92 or 0.44))
                cursor = cursor + peak.width
            end
            assert(math.abs(cursor - range.right) < 1e-9)
        end
    end)
    Test("单格与细长地图每个非平原格恰好覆盖一次", function()
        for _, rows in ipairs({{"m"}, {"h"}, {"mhmp"}, {"m", "h", "m"}}) do
            local world = Fixture(rows)
            local geometry = Backdrop.Geometry(world)
            local covered = {}
            for _, range in ipairs(geometry.ranges) do
                for x = range.left, range.right do
                    local i = (range.row - 1) * world.width + x
                    assert(not covered[i] and world.cells[i].terrainKind == range.kind)
                    covered[i] = true
                end
            end
            for i, cell in ipairs(world.cells) do assert((covered[i] == true) == (cell.terrainKind ~= "plain")) end
        end
    end)
    Test("世代推进复用同一底图，新世界重建底图", function()
        local world = Simulation.New()
        local geometry = Backdrop.Geometry(world)
        Simulation.Tick(world)
        assert(Backdrop.Geometry(world) == geometry)
        assert(Backdrop.Geometry(Simulation.New()) ~= geometry)
    end)
    Test("多种子底图不修改地形、经济数据或模拟随机流", function()
        for seed = 1, 16 do
            local world, reference = Simulation.New(seed * 7919), Simulation.New(seed * 7919)
            Backdrop.Geometry(world)
            Simulation.Tick(world); Simulation.Tick(reference)
            for i, cell in ipairs(world.cells) do
                for key, value in pairs(cell) do assert(value == reference.cells[i][key], key) end
            end
            assert(world.rng.state == reference.rng.state and world.rng.draws == reference.rng.draws)
        end
    end)
    Test("统计视图只有勾线与细纹，地形视图才有填色及阴影", function()
        local names = {"nvgSave", "nvgRestore", "nvgIntersectScissor", "nvgBeginPath", "nvgMoveTo",
            "nvgLineTo", "nvgBezierTo", "nvgQuadTo", "nvgClosePath", "nvgRect", "nvgFillPaint",
            "nvgLinearGradient", "nvgFillColor", "nvgRGBA", "nvgStrokeColor", "nvgStrokeWidth", "nvgFill", "nvgStroke"}
        local saved, counts = {}, {fills = 0, strokes = 0}
        for _, name in ipairs(names) do saved[name] = _G[name]; _G[name] = function() return {} end end
        _G.nvgFill = function() counts.fills = counts.fills + 1 end
        _G.nvgStroke = function() counts.strokes = counts.strokes + 1 end
        local ok, err = pcall(function()
            local world = Fixture({"mmhhp"})
            local b = {x = 0, y = 0, w = 300, h = 60, cw = 60, ch = 60}
            for _, layer in ipairs({"quality", "population", "institution", "terrain"}) do
                counts.fills, counts.strokes = 0, 0
                Backdrop.Draw({}, world, b, layer)
                assert(counts.strokes > 0, layer .. " missing outlines")
                assert((counts.fills > 0) == (layer == "terrain"), layer .. " unexpected terrain fill")
            end
        end)
        for _, name in ipairs(names) do _G[name] = saved[name] end
        assert(ok, err)
    end)
    report.ok = report.failed == 0
    return report
end

return Tests
