-- 技术流的筛选与箭头几何；只读取上一世代的真实传播，不改变模拟。
local V = {}
local Evolution = require("OriginEvolution")

---@param relativeGain number 本次学习相对于接收方原有技术的增幅
---@param cellSize number
---@return number
function V.Width(relativeGain, cellSize)
    local minimum = math.min(0.85, cellSize * 0.025)
    local maximum = math.min(9.0, cellSize * 0.24)
    local strength = math.max(0, relativeGain)
    -- 真实记录大多在0.01%～0.6%之间；按此量级拉开细、中、粗，强流平滑封顶。
    return minimum + (maximum - minimum) * strength / (strength + 0.0010)
end

---@param world table
---@param bounds table
---@param viewport table
---@param global boolean
---@param selectedIndex integer
---@return table[]
function V.Arrows(world, bounds, viewport, global, selectedIndex, report)
    local arrows = {}
    local size = math.min(bounds.cw, bounds.ch)
    report = report or world.lastReport
    for _, flow in ipairs(report and report.technologyFlows or {}) do
        local source, target = world.cells[flow.from], world.cells[flow.to]
        if source and target and flow.amount > 0 and flow.relativeGain > 0
            and math.abs(target.x - source.x) + math.abs(target.y - source.y) == 1
            and (global or flow.from == selectedIndex or flow.to == selectedIndex) then
            local dx, dy = (target.x - source.x) * bounds.cw, (target.y - source.y) * bounds.ch
            local distance = math.sqrt(dx * dx + dy * dy)
            local ux, uy = dx / distance, dy / distance
            local nx, ny = -uy, ux
            -- 两种技术各占一条通道，反向流在中心线另一侧，避免相互盖住。
            local lane = size * (flow.kind == "agriculture" and 0.06 or 0.29)
            local cx = bounds.x + (source.x - 0.5) * bounds.cw + nx * lane
            local cy = bounds.y + (source.y - 0.5) * bounds.ch + ny * lane
            local startX, startY = cx + dx * 0.10, cy + dy * 0.10
            local tipX, tipY = cx + dx * 0.90, cy + dy * 0.90
            local width = V.Width(flow.relativeGain, size)
            local length = distance * 0.80
            local headLength = math.min(length * 0.24, math.max(3.2, width * 1.55))
            local headHalf = math.min(size * 0.18, math.max(1.4, width * 0.90))
            local shaftLength = math.min(length * 0.10, math.max(1.6, width * 0.85))
            local minX, maxX, minY, maxY = math.huge, -math.huge, math.huge, -math.huge
            for _, p in ipairs({{startX, startY}, {tipX, tipY}}) do
                minX, maxX = math.min(minX, p[1] - math.abs(nx) * headHalf), math.max(maxX, p[1] + math.abs(nx) * headHalf)
                minY, maxY = math.min(minY, p[2] - math.abs(ny) * headHalf), math.max(maxY, p[2] + math.abs(ny) * headHalf)
            end
            if maxX >= viewport.x and minX <= viewport.x + viewport.w
                and maxY >= viewport.y and minY <= viewport.y + viewport.h then
                arrows[#arrows + 1] = {
                    from = flow.from, to = flow.to, kind = flow.kind, width = width,
                    startX = startX, startY = startY, tipX = tipX, tipY = tipY,
                    ux = ux, uy = uy, length = length, headLength = headLength,
                    headHalf = headHalf, shaftLength = shaftLength,
                    color = flow.kind == "agriculture" and {0, 151, 235, 255} or {32, 74, 218, 255},
                }
            end
        end
    end
    return arrows
end

-- 移动与消失共用沿路径的线速度；消失只是将原有拖尾渐变向箭尖平移。
V.TrailFraction = 0.28

---@param arrow table
---@return table
function V.Timing(arrow, duration)
    duration = duration or Evolution.GenerationSeconds
    local body = arrow.headLength + arrow.shaftLength
    local speed = arrow.length * (1 + V.TrailFraction) / duration
    local move = (arrow.length - body) / speed
    local erase = (body + arrow.length * V.TrailFraction) / speed
    return {move = move, erase = erase, speed = speed, duration = duration, cycle = duration}
end

---@param arrow table
---@param elapsed number
---@param duration number?
---@return table? moving
function V.Moving(arrow, elapsed, duration)
    local timing = V.Timing(arrow, duration)
    if elapsed < 0 or elapsed >= timing.duration then return nil end
    local bodyLength = arrow.headLength + arrow.shaftLength
    local front = bodyLength + timing.speed * math.min(elapsed, timing.move)
    local bodyStart = front - bodyLength
    local base = front - arrow.headLength
    local tailStart = math.max(0, bodyStart - arrow.length * V.TrailFraction)
    local trailLength = bodyStart - tailStart
    local half = arrow.width / 2
    local function Point(along, across)
        return {arrow.startX + arrow.ux * along - arrow.uy * across,
            arrow.startY + arrow.uy * along + arrow.ux * across}
    end
    local moving = {points = {
        Point(bodyStart, half), Point(base, half), Point(base, arrow.headHalf), Point(front, 0),
        Point(base, -arrow.headHalf), Point(base, -half), Point(bodyStart, -half),
    }, tipX = arrow.startX + arrow.ux * front, tipY = arrow.startY + arrow.uy * front,
        erasing = elapsed > timing.move}
    if trailLength > 0.000001 then
        moving.tail = {points = {Point(tailStart, half * 0.15), Point(bodyStart, half),
            Point(bodyStart, -half), Point(tailStart, -half * 0.15)}}
        local gradientStart = tailStart + timing.speed * math.max(0, elapsed - timing.move)
        moving.gradient = {
            x1 = arrow.startX + arrow.ux * gradientStart, y1 = arrow.startY + arrow.uy * gradientStart,
            x2 = arrow.startX + arrow.ux * (gradientStart + trailLength),
            y2 = arrow.startY + arrow.uy * (gradientStart + trailLength),
        }
    end
    return moving
end

return V
