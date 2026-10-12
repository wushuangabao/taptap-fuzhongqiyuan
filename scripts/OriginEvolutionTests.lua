local E = require("OriginEvolution")
local S = require("OriginSimulation")
local T = {}

local function Same(a, b)
    assert(type(a) == type(b))
    if type(a) ~= "table" then assert(a == b); return end
    for k, v in pairs(a) do Same(v, b[k]) end
    for k in pairs(b) do assert(a[k] ~= nil) end
end

function T.Run()
    local result = {passed = 0, failed = 0, results = {}}
    local function Test(name, fn)
        local ok, err = pcall(fn)
        result[ok and "passed" or "failed"] = result[ok and "passed" or "failed"] + 1
        result.results[#result.results + 1] = {name = name, passed = ok, error = not ok and tostring(err) or nil}
    end
    Test("预计算不改当前世界，提交与直接模拟逐字段一致", function()
        local world, direct = S.New(20261002), S.New(20261002)
        local ctx = {world = world, accumulator = 0}
        for _ = 1, 10 do
            S.ApplyAction(world, "skip", 12, 8)
            S.ApplyAction(direct, "skip", 12, 8)
            for _ = 1, 5 do
                E.Prepare(ctx)
                Same(world, direct)
                local pending = ctx.pendingGeneration
                E.Prepare(ctx)
                assert(ctx.pendingGeneration == pending)
                E.Commit(ctx)
                S.Tick(direct)
                Same(world, direct)
                assert(not ctx.pendingGeneration and ctx.accumulator == 0)
            end
        end
    end)
    Test("三个倍率一轮均播放五次完整动画，到期才提交", function()
        assert(E.GenerationSeconds == 4)
        for _, speed in ipairs({1, 2, 4}) do
            local ctx = {world = S.New(42), accumulator = 0, phase = "simulation", speed = speed}
            local frames = 0
            for generation = 1, 5 do
                E.Prepare(ctx)
                assert(ctx.pendingGeneration.lastReport.generation == generation)
                while not E.Update(ctx, 0.25) do
                    frames = frames + 1
                    assert(ctx.world.generation == generation - 1)
                end
                frames = frames + 1
                assert(E.Migration(ctx.accumulator) == nil)
                E.Commit(ctx)
                assert(ctx.world.generation == generation and not ctx.pendingGeneration)
            end
            assert(frames * 0.25 == 5 * E.GenerationSeconds / speed)
        end
    end)
    Test("暂停弹窗竖屏冻结；切换倍速不跳进度；重开清空待提交结果", function()
        local ctx = {world = S.New(15), accumulator = 0, phase = "simulation", speed = 1}
        E.Update(ctx, 0.5)
        local pending = ctx.pendingGeneration
        for _, gate in ipairs({"paused", "modalOpen", "portraitBlocked"}) do
            ctx[gate] = true
            assert(not E.Update(ctx, 20) and ctx.accumulator == 0.5)
            ctx[gate] = false
        end
        ctx.speed = 4
        assert(ctx.accumulator == 0.5 and ctx.pendingGeneration == pending)
        E.Update(ctx, 0.25)
        assert(ctx.accumulator == 1.5 and ctx.world.generation == 0)
        E.Reset(ctx)
        assert(ctx.accumulator == 0 and not ctx.pendingGeneration)
        ctx.phase = "decision"
        assert(not E.Update(ctx, 20) and not ctx.pendingGeneration)
    end)
    Test("迁移光点先移动后渐隐，可控时长结束后持续隐藏", function()
        for _, duration in ipairs({3, 10, 20}) do
            assert(E.Migration(0, duration).position == 0)
            assert(E.Migration(duration * .5, duration).position < 1)
            assert(E.Migration(duration * .75, duration).position == 1)
            local fading = E.Migration(duration * .875, duration)
            assert(fading.position == 1 and fading.alpha == .5)
            assert(E.Migration(duration, duration) == nil)
            assert(E.Migration(duration * 2, duration) == nil)
        end
    end)
    result.ok = result.failed == 0
    return result
end

return T
