-- 舆图式地貌底板：成片淡染，侧面山脊勾线与皴笔；不画闭合等高线。
-- 所有山势使用地图坐标，农田、房屋和数值由 OriginWidgets 随后覆盖绘制。
local Backdrop = {}

---@class OriginReliefPeak
---@field x number
---@field width number
---@field height number
---@field lean number

---@class OriginReliefRange
---@field kind string
---@field group integer
---@field row integer
---@field left integer
---@field right integer
---@field peaks OriginReliefPeak[]

---@class OriginReliefGeometry
---@field ranges OriginReliefRange[]
---@field groupIds table<number, integer>
---@field groups integer

---@type table<table, OriginReliefGeometry>
local cache = setmetatable({}, {__mode = "k"})

-- 装饰用确定性扰动，不消耗游戏随机流。
local function Variation(x, y, salt)
    local value = math.sin(x * 127.1 + y * 311.7 + salt * 74.7) * 43758.5453
    return value - math.floor(value)
end

---@param world OriginWorld
---@return OriginReliefGeometry
function Backdrop.Geometry(world)
    if cache[world] then return cache[world] end
    ---@type OriginReliefGeometry
    local geometry = {ranges = {}, groupIds = {}, groups = 0}
    local w, h = world.config.width, world.config.height
    local groupIds = geometry.groupIds
    -- 同类四邻域共用一片底板；平原孔洞和仅对角接触的山体不合并。
    for i, cell in ipairs(world.cells) do
        if cell.terrainKind ~= "plain" and not groupIds[i] then
            geometry.groups = geometry.groups + 1
            groupIds[i] = geometry.groups
            local queue, head = {i}, 1
            while head <= #queue do
                local index = queue[head]
                head = head + 1
                local x, y = (index - 1) % w + 1, (index - 1) // w + 1
                for _, offset in ipairs({{-1, 0}, {1, 0}, {0, -1}, {0, 1}}) do
                    local nx, ny = x + offset[1], y + offset[2]
                    local neighbor = (ny - 1) * w + nx
                    if nx >= 1 and nx <= w and ny >= 1 and ny <= h and not groupIds[neighbor]
                        and world.cells[neighbor].terrainKind == cell.terrainKind then
                        groupIds[neighbor] = geometry.groups
                        queue[#queue + 1] = neighbor
                    end
                end
            end
        end
    end
    -- 每一横向连片是一条完整山脊；峰顶不对齐格心，不重复逐格贴小图标。
    for y = 1, h do
        local x = 1
        while x <= w do
            local cell = world.cells[(y - 1) * w + x]
            if cell.terrainKind == "plain" then
                x = x + 1
            else
                local left, kind, group = x, cell.terrainKind, groupIds[(y - 1) * w + x]
                repeat x = x + 1
                until x > w or world.cells[(y - 1) * w + x].terrainKind ~= kind
                local span = x - left
                local count = math.max(1, math.floor(span / (kind == "mountain" and 1.15 or 1.6) + 0.5))
                ---@type OriginReliefRange
                local range = {kind = kind, group = group, row = y, left = left, right = x - 1, peaks = {}}
                local weights, total = {}, 0
                for k = 1, count do
                    weights[k] = 0.8 + Variation(left + k, y, 1) * 0.5
                    total = total + weights[k]
                end
                local start = left - 1
                for k = 1, count do
                    local width = span * weights[k] / total
                    local tall = kind == "mountain"
                    range.peaks[#range.peaks + 1] = {x = start, width = width,
                        height = (tall and 0.67 or 0.25) + Variation(left + k, y, 2) * (tall and 0.25 or 0.19),
                        lean = 0.35 + Variation(left + k, y, 3) * 0.20}
                    start = start + width
                end
                geometry.ranges[#geometry.ranges + 1] = range
            end
        end
    end
    cache[world] = geometry
    return geometry
end

---@param vg NVGContextWrapper
---@param range OriginReliefRange
---@param b table
local function Skyline(vg, range, b)
    local base = b.y + (range.row - 0.05) * b.ch
    local start = b.x + (range.left - 1) * b.cw
    nvgBeginPath(vg)
    nvgMoveTo(vg, start, base)
    for _, peak in ipairs(range.peaks) do
        local x, w, h = b.x + peak.x * b.cw, peak.width * b.cw, peak.height * b.ch
        local summit = x + w * peak.lean
        if range.kind == "mountain" then
            -- 不对称峰肩、折落的石壁与鞍部，避免等边三角形的符号感。
            nvgBezierTo(vg, x + w * 0.08, base - h * 0.17, x + w * 0.12, base - h * 0.37,
                x + w * 0.23, base - h * 0.46)
            nvgLineTo(vg, summit - w * 0.07, base - h * 0.82)
            nvgQuadTo(vg, summit - w * 0.03, base - h * 1.02, summit + w * 0.02, base - h)
            nvgLineTo(vg, summit + w * 0.10, base - h * 0.77)
            nvgLineTo(vg, summit + w * 0.17, base - h * 0.70)
            nvgBezierTo(vg, x + w * 0.77, base - h * 0.25, x + w * 0.77, base - h * 0.39,
                x + w * 0.87, base - h * 0.16)
            nvgQuadTo(vg, x + w * 0.94, base - h * 0.07, x + w, base)
        else
            -- 丘陵是宽而矮的土坡，顶线舒展，和高山的峻折侧影分开。
            nvgBezierTo(vg, x + w * 0.08, base - h * 0.04, x + w * 0.13, base - h * 0.86,
                summit - w * 0.04, base - h * 0.98)
            nvgBezierTo(vg, summit + w * 0.18, base - h * 1.09, x + w * 0.72, base - h * 0.38,
                x + w, base)
        end
    end
end

---@param vg NVGContextWrapper
---@param range OriginReliefRange
---@param b table
---@param strength number
---@param colored boolean
local function DrawRange(vg, range, b, strength, colored)
    local tall = range.kind == "mountain"
    local base = b.y + (range.row - 0.05) * b.ch
    local left, right = b.x + (range.left - 1) * b.cw, b.x + range.right * b.cw
    local stroke = math.max(0.8, math.min(1.6, b.cw / 48))
    if colored then
        Skyline(vg, range, b)
        nvgLineTo(vg, right, base + b.ch * 0.05)
        nvgLineTo(vg, left, base + b.ch * 0.05)
        nvgClosePath(vg)
        local wash = tall and {101, 121, 108} or {156, 132, 78}
        nvgFillPaint(vg, nvgLinearGradient(vg, left, base - b.ch * (tall and 0.82 or 0.42), left, base,
            nvgRGBA(wash[1], wash[2], wash[3], math.floor(98 * strength)),
            nvgRGBA(wash[1], wash[2], wash[3], 0)))
        nvgFill(vg)
    end
    -- 只勾山脊，不描封闭底边；山脚淡入地面，避免水滴/封闭色斑。
    Skyline(vg, range, b)
    nvgStrokeColor(vg, tall and nvgRGBA(74, 94, 77, math.floor(160 * strength))
        or nvgRGBA(117, 100, 60, math.floor(155 * strength)))
    nvgStrokeWidth(vg, stroke)
    nvgStroke(vg)
    for _, peak in ipairs(range.peaks) do
        local x, w, h = b.x + peak.x * b.cw, peak.width * b.cw, peak.height * b.ch
        local summit = x + w * peak.lean
        if tall and colored then
            -- 一侧淡墨石面，顺着山脊分叉的细皴线，前景信息仍覆盖在上面。
            nvgBeginPath(vg)
            nvgMoveTo(vg, summit + w * 0.02, base - h * 0.94)
            nvgBezierTo(vg, summit - w * 0.07, base - h * 0.67, summit + w * 0.18, base - h * 0.31,
                x + w * 0.48, base - h * 0.05)
            nvgQuadTo(vg, x + w * 0.76, base - h * 0.08, x + w * 0.87, base - h * 0.16)
            nvgLineTo(vg, summit + w * 0.17, base - h * 0.70)
            nvgClosePath(vg)
            nvgFillPaint(vg, nvgLinearGradient(vg, summit, base - h, summit + w * 0.15, base,
                nvgRGBA(68, 90, 74, math.floor(64 * strength)), nvgRGBA(87, 108, 86, 0)))
            nvgFill(vg)
        end
        nvgBeginPath(vg)
        local strokes = tall and 4 or 3
        for k = 1, strokes do
            local t = k / (strokes + 1)
            if tall then
                local sx = summit + w * (0.035 + t * 0.20)
                local sy = base - h * (0.84 - t * 0.35)
                nvgMoveTo(vg, sx, sy)
                nvgBezierTo(vg, sx - w * 0.035, sy + h * 0.17,
                    sx + w * 0.085, base - h * 0.28, x + w * (0.51 + t * 0.29), base - h * 0.09)
            else
                local sx = x + w * (0.20 + t * 0.22)
                nvgMoveTo(vg, sx, base - h * (0.63 - t * 0.12))
                nvgBezierTo(vg, sx + w * 0.06, base - h * 0.78,
                    x + w * (0.54 + t * 0.08), base - h * 0.35,
                    x + w * (0.60 + t * 0.17), base - h * 0.16)
            end
        end
        nvgStrokeColor(vg, tall and nvgRGBA(82, 101, 81, math.floor(105 * strength))
            or nvgRGBA(132, 111, 66, math.floor(105 * strength)))
        nvgStrokeWidth(vg, stroke * 0.65)
        nvgStroke(vg)
    end
end

---@param vg NVGContextWrapper
---@param world OriginWorld
---@param b table
---@param layer string
function Backdrop.Draw(vg, world, b, layer)
    local geometry = Backdrop.Geometry(world)
    local colored = layer == "terrain"
    local strength = colored and 1 or 0.78
    nvgSave(vg)
    nvgIntersectScissor(vg, b.x, b.y, b.w, b.h)
    -- 连片薄底在山脊之间延续，只铺真实的山地/丘陵，绝不填平原孔洞。
    for _, range in ipairs(colored and geometry.ranges or {}) do
        nvgBeginPath(vg)
        nvgRect(vg, b.x + (range.left - 1) * b.cw, b.y + (range.row - 1) * b.ch,
            (range.right - range.left + 1) * b.cw, b.ch)
        nvgFillColor(vg, range.kind == "mountain" and nvgRGBA(131, 151, 138, math.floor(52 * strength))
            or nvgRGBA(193, 165, 101, math.floor(65 * strength)))
        nvgFill(vg)
    end
    for _, range in ipairs(geometry.ranges) do DrawRange(vg, range, b, strength, colored) end
    nvgRestore(vg)
end

return Backdrop
