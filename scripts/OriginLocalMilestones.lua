-- 局部成果只观察成功行动与真实世代报告，不修改世界、不抽随机数、不发奖励。
local S = require("OriginSimulation")
local M = {}

---@class OriginLocalEvent
---@field kind string
---@field title string
---@field detail string
---@field generation integer
---@field round integer
---@field action OriginActionRecord
---@field region table
---@field evidence table

---@class OriginLocalProgress
---@field completed table<string, OriginLocalEvent>
---@field history OriginLocalEvent[]
---@field pending table?
---@field world OriginWorld?

---@return OriginLocalProgress
function M.New()
    return {completed = {}, history = {}}
end

local function Copy(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, item in pairs(value) do result[key] = Copy(item) end
    return result
end

-- 必须在 ApplyAction 之前调用；无效行动不会产生候选。
---@param world OriginWorld
---@param action string
---@param x integer
---@param y integer
---@param withProtection boolean?
---@return table?
function M.Capture(world, action, x, y, withProtection)
    if not S.ValidateAction(world, action, x, y, withProtection) then return nil end
    local candidate = {action = action, x = x, y = y, size = world.config.regionSize,
        generation = world.generation, actionCount = #world.actions, before = {}, indices = {}}
    for cy = y, y + candidate.size - 1 do
        for cx = x, x + candidate.size - 1 do
            local index = (cy - 1) * world.config.width + cx
            candidate.indices[index] = true
            if S.IsHabitable(world.cells[index]) then candidate.before[index] = Copy(world.cells[index]) end
        end
    end
    return candidate
end

-- 仅绑定刚刚成功写入的同一个行动；原有探索制度和未实际改变的格子不算。
---@param state OriginLocalProgress
---@param world OriginWorld
---@param candidate table?
---@return boolean
function M.CommitAction(state, world, candidate)
    if not candidate or (state.world and state.world ~= world) then return false end
    local record = world.actions[#world.actions]
    if #world.actions ~= candidate.actionCount + 1 or not record
        or record.action ~= candidate.action or record.x ~= candidate.x or record.y ~= candidate.y
        or record.generation ~= candidate.generation or world.generation ~= candidate.generation then return false end
    if state.pending and state.pending.action.round == record.round then return false end
    local pending = {action = Copy(record), region = {x = candidate.x, y = candidate.y, size = candidate.size},
        indices = Copy(candidate.indices), hungry = {}, exploring = {}, technology = {}, lastGeneration = world.generation,
        endGeneration = world.generation + world.config.generationsPerRound}
    for index, before in pairs(candidate.before) do
        local after = world.cells[index]
        if (record.action == "agriculture" and after.agriculture > before.agriculture)
            or (record.action == "foodUp" and after.foodShare > before.foodShare) then
            if S.Metrics(before, world.config).foodRatio < 1 then pending.hungry[index] = true end
        end
        if record.action == "institution" and before.institution ~= world.config.exploreInstitution
            and after.institution == world.config.exploreInstitution then pending.exploring[index] = true end
        if record.action == "agriculture" and after.agriculture > before.agriculture then
            pending.technology[index] = "agriculture"
        elseif record.action == "craft" and after.craft > before.craft then pending.technology[index] = "craft" end
    end
    pending.exploringTotal = 0
    for _ in pairs(pending.exploring) do pending.exploringTotal = pending.exploringTotal + 1 end
    state.world, state.pending = world, pending
    return true
end

---@param state OriginLocalProgress
---@param pending table
---@param report OriginReport
---@param kind string
---@param title string
---@param detail string
---@param evidence table
---@param emitted OriginLocalEvent[]
local function Complete(state, pending, report, kind, title, detail, evidence, emitted)
    if state.completed[kind] then return end
    ---@type OriginLocalEvent
    local event = {kind = kind, title = title, detail = detail, generation = report.generation,
        round = pending.action.round, action = Copy(pending.action), region = Copy(pending.region), evidence = Copy(evidence)}
    state.completed[kind] = event
    state.history[#state.history + 1] = event
    emitted[#emitted + 1] = event
end

-- 顺序补读历史，不用当前选区或当前格子替代过去证据。重复调用不重新完成。
---@param state OriginLocalProgress
---@param world OriginWorld
---@return OriginLocalEvent[]
function M.Evaluate(state, world)
    ---@type OriginLocalEvent[]
    local emitted = {}
    local pending = state.pending
    if not pending or state.world ~= world then return emitted end
    for generation = pending.lastGeneration + 1, math.min(world.generation, pending.endGeneration) do
        local report = world.history[generation + 1]
        if not report or report.initial or report.generation ~= generation or report.round ~= pending.action.round then break end
        -- 一旦被替代就失去连续存续资格；后来恢复探索型也不能补算。
        for index in pairs(pending.exploring) do
            local delta = report.deltas[index]
            if not delta or delta.before.institution ~= world.config.exploreInstitution
                or delta.after.institution ~= world.config.exploreInstitution then pending.exploring[index] = nil end
        end
        for _, flow in ipairs(report.technologyFlows or {}) do
            if pending.technology[flow.from] == flow.kind and not pending.indices[flow.to] and flow.amount > 0 then
                local adjacent = false
                for _, index in ipairs(world.neighbors[flow.from] or {}) do if index == flow.to then adjacent = true end end
                if adjacent then
                    Complete(state, pending, report, "technology", "技术开始传向周边",
                        "本轮提高过的技术，已从干预区传到周边。这里记录的是实际学习过程。",
                        {flow = flow}, emitted)
                end
            end
        end
        if generation == pending.endGeneration then
            local fed, hungry = {}, 0
            for index in pairs(pending.hungry) do
                hungry = hungry + 1
                local delta = report.deltas[index]
                if delta and S.Metrics(delta.after, world.config).foodRatio >= 1 then fed[#fed + 1] = index end
            end
            table.sort(fed)
            if #fed > 0 then
                local degree = #fed == hungry and "大幅" or (#fed * 2 >= hungry and "明显" or "少许")
                Complete(state, pending, report, "food", "温饱有了" .. degree .. "改善",
                    "本轮干预后，这片土地上原本缺粮的居民开始吃得饱了。迁移与自然演进也会影响温饱。",
                    {fedIndices = fed, hungryTotal = hungry}, emitted)
            end
            local survived = {}
            for index in pairs(pending.exploring) do survived[#survived + 1] = index end
            table.sort(survived)
            if pending.exploringTotal > 0 and #survived * 2 >= pending.exploringTotal then
                Complete(state, pending, report, "exploration", "探索制度站稳了脚跟",
                    "新建立的探索制度在这片土地上撑过了一整轮。此刻的存续，还需要往后继续观察。",
                    {survivedIndices = survived, establishedTotal = pending.exploringTotal}, emitted)
            end
        end
        pending.lastGeneration = generation
    end
    if pending.lastGeneration >= pending.endGeneration then state.pending = nil end
    return emitted
end

return M
