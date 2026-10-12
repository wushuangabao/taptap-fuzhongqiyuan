-- 播放时序独立于模拟规则：一代的真实流动播放完毕后，才提交这一代。
local S = require("OriginSimulation")
local E = {}

-- 正常倍速下一代的完整播放时长（秒）；箭头和迁移光点共用此值。
E.GenerationSeconds = 4
E.MigrationMoveFraction = 0.75

-- 所有游戏时钟共用暂停门闩；面板临时暂停不覆盖玩家的手动暂停状态。
function E.IsPaused(ctx)
    return ctx.paused or ctx.modalOpen or ctx.portraitBlocked
end

local function Copy(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, item in pairs(value) do result[key] = Copy(item) end
    return result
end

function E.Reset(ctx)
    ctx.pendingGeneration = nil
    ctx.accumulator = 0
end

function E.Prepare(ctx)
    if ctx.pendingGeneration then return end
    ---@type OriginWorld
    local nextWorld = {}
    for key, value in pairs(ctx.world) do
        -- 历史记录只追加，不被 Tick 改写；无需逐代复制整局历史。
        if key == "history" then
            nextWorld.history = {table.unpack(value)}
        elseif key ~= "lastReport" then
            nextWorld[key] = Copy(value)
        end
    end
    S.Tick(nextWorld)
    ctx.pendingGeneration = nextWorld
end

function E.Commit(ctx)
    E.Prepare(ctx)
    local pending = ctx.pendingGeneration
    for key, value in pairs(pending) do ctx.world[key] = value end
    E.Reset(ctx)
    return ctx.world.lastReport
end

function E.Update(ctx, dt)
    if ctx.phase ~= "simulation" or E.IsPaused(ctx) then return false end
    E.Prepare(ctx)
    ctx.accumulator = math.min(E.GenerationSeconds, ctx.accumulator + dt * ctx.speed)
    return ctx.accumulator >= E.GenerationSeconds
end

-- 移动到终点后，光点、光晕和拖尾一起渐隐；到期后保持消失，不循环。
function E.Migration(elapsed, duration)
    duration = duration or E.GenerationSeconds
    if elapsed < 0 or elapsed >= duration then return nil end
    local progress = elapsed / duration
    return {position = math.min(1, progress / E.MigrationMoveFraction),
        alpha = math.min(1, (1 - progress) / (1 - E.MigrationMoveFraction))}
end

return E
