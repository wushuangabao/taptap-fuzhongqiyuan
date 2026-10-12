-- 文明图谱的矢量表现层。只绘制数据，不调用模拟随机数。
local UI = require("urhox-libs/UI")
local Camera = require("OriginCamera")
local RegionLayout = require("OriginRegionLayout")
local RegionLabelAtlas = require("OriginRegionLabelAtlas")
local TerrainBackdrop = require("OriginTerrainBackdrop")
local CellVisuals = require("OriginCellVisuals")
local TechnologyVisuals = require("OriginTechnologyVisuals")
local Evolution = require("OriginEvolution")
-- UI context owns this one atlas; cache it instead of allocating each frame.
local regionLabelImages = setmetatable({}, {__mode = "k"})
local W = {}

W.Colors = {
    ink = {35, 56, 45, 255}, muted = {122, 131, 117, 255},
    paper = {246, 245, 235, 255}, card = {255, 254, 247, 255},
    line = {222, 225, 210, 255}, green = {66, 111, 72, 255},
    gold = {185, 143, 61, 255}, teal = {57, 148, 135, 255},
    red = {190, 93, 73, 255}, soil = {166, 149, 113, 255},
}

local function Color(c, alpha)
    return nvgRGBA(math.floor(c[1]), math.floor(c[2]), math.floor(c[3]), math.floor(alpha or c[4] or 255))
end

local function Rect(vg, x, y, w, h, c, radius)
    nvgBeginPath(vg)
    if radius and radius > 0 then
        nvgRoundedRect(vg, x, y, math.max(0, w), math.max(0, h), radius)
    else
        nvgRect(vg, x, y, math.max(0, w), math.max(0, h))
    end
    nvgFillColor(vg, Color(c))
    nvgFill(vg)
end

local function Line(vg, x1, y1, x2, y2, c, width)
    nvgBeginPath(vg)
    nvgMoveTo(vg, x1, y1)
    nvgLineTo(vg, x2, y2)
    nvgStrokeWidth(vg, width or 1)
    nvgStrokeColor(vg, Color(c))
    nvgStroke(vg)
end

local function Circle(vg, x, y, r, c)
    nvgBeginPath(vg)
    nvgCircle(vg, x, y, math.max(0, r))
    nvgFillColor(vg, Color(c))
    nvgFill(vg)
end

local function Outline(vg, x, y, w, h, c, thickness, radius)
    nvgBeginPath(vg)
    nvgRoundedRect(vg, x, y, w, h, radius or 0)
    nvgStrokeColor(vg, Color(c))
    nvgStrokeWidth(vg, thickness or 1)
    nvgStroke(vg)
end

local function Mix(a, b, t)
    t = math.max(0, math.min(1, t))
    return {a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t, a[3] + (b[3] - a[3]) * t, 255}
end

local function Rose(vg, x, y, r)
    -- 顶部用品统计与地图共用花茎、叶片和卷瓣，保持玫瑰标识一致。
    Line(vg, x, y + r, x, y + r * 2.15, {63, 115, 68, 255}, r * 0.42)
    nvgBeginPath(vg)
    nvgMoveTo(vg, x, y + r * 1.9)
    nvgQuadTo(vg, x - r * 1.5, y + r * 0.7, x - r * 1.4, y + r * 1.4)
    nvgQuadTo(vg, x - r * 0.7, y + r * 2.1, x, y + r * 1.9)
    nvgFillColor(vg, nvgRGBA(72, 132, 72, 255)); nvgFill(vg)
    -- 各花瓣共用一次填充，避免小图标出现多层暗边。
    nvgBeginPath(vg)
    for petal = 0, 4 do
        local angle = petal * math.pi * 2 / 5
        nvgCircle(vg, x + math.cos(angle) * r * 0.48, y + math.sin(angle) * r * 0.48, r * 0.67)
    end
    nvgFillColor(vg, nvgRGBA(185, 59, 88, 255)); nvgFill(vg)
    nvgBeginPath(vg)
    nvgMoveTo(vg, x - r * 0.48, y)
    nvgBezierTo(vg, x - r * 0.45, y - r * 0.70, x + r * 0.65, y - r * 0.48, x + r * 0.32, y + r * 0.18)
    nvgQuadTo(vg, x, y + r * 0.46, x - r * 0.12, y + r * 0.08)
    nvgStrokeColor(vg, nvgRGBA(244, 155, 162, 255)); nvgStrokeWidth(vg, r * 0.30); nvgStroke(vg)
end

---@class OriginIcon : Widget
---@field kind string
---@field color table
local Icon = UI.Widget:Extend("OriginIcon")

function Icon:Init(props)
    UI.Widget.Init(self, props)
    self.kind = props.kind or "leaf"
    self.color = props.color or W.Colors.green
end

function Icon:Render(vg)
    local l = self:GetAbsoluteLayout()
    local size = math.min(l.w, l.h)
    local x, y = l.x + l.w / 2, l.y + l.h / 2
    local r = size * 0.35
    local c = self.color
    nvgSave(vg)
    nvgStrokeColor(vg, Color(c))
    nvgStrokeWidth(vg, 1.6)
    if self.kind == "leaf" or self.kind == "agriculture" then
        Line(vg, x, y + r, x, y - r, c, 1.6)
        for k = 1, 3 do
            local py = y + r * 0.4 - k * r * 0.5
            Line(vg, x, py + r * 0.35, x - r * 0.7, py - r * 0.1, c, 2)
            Line(vg, x, py + r * 0.35, x + r * 0.7, py - r * 0.1, c, 2)
        end
    elseif self.kind == "rose" then
        Rose(vg, x, y - size * 0.12, size * 0.24)
    elseif self.kind == "craft" then
        nvgBeginPath(vg)
        nvgMoveTo(vg, x - r, y - r * 0.45)
        nvgLineTo(vg, x + r * 0.4, y - r * 0.45)
        nvgLineTo(vg, x + r, y - r)
        nvgLineTo(vg, x + r, y + r * 0.1)
        nvgLineTo(vg, x + r * 0.2, y + r * 0.5)
        nvgLineTo(vg, x - r * 0.55, y + r * 0.5)
        nvgClosePath(vg)
        nvgStroke(vg)
        Line(vg, x, y + r * 0.5, x, y + r, c, 1.6)
        Line(vg, x - r * 0.6, y + r, x + r * 0.6, y + r, c, 1.6)
    elseif self.kind == "institution" then
        Circle(vg, x, y, r * 0.35, c)
        for k = 1, 8 do
            local a = k * math.pi / 4
            Line(vg, x + math.cos(a) * r * 0.65, y + math.sin(a) * r * 0.65,
                x + math.cos(a) * r, y + math.sin(a) * r, c, 1.5)
        end
    elseif self.kind == "protect" then
        nvgBeginPath(vg)
        nvgMoveTo(vg, x, y - r)
        nvgLineTo(vg, x + r * 0.8, y - r * 0.6)
        nvgLineTo(vg, x + r * 0.65, y + r * 0.4)
        nvgLineTo(vg, x, y + r)
        nvgLineTo(vg, x - r * 0.65, y + r * 0.4)
        nvgLineTo(vg, x - r * 0.8, y - r * 0.6)
        nvgClosePath(vg)
        nvgStroke(vg)
    elseif self.kind == "population" then
        -- 三个完整半身像；头身与人物之间留白，保证 16px 下仍能辨认。
        for person = -1, 1 do
            local center = person == 0
            local px = x + person * size * 0.31
            local headY = y - size * (center and 0.30 or 0.16)
            local headR = size * (center and 0.115 or 0.09)
            local shoulderY = headY + headR + size * 0.075
            local halfWidth = size * (center and 0.15 or 0.12)
            local bottomY = y + size * (center and 0.35 or 0.24)
            Circle(vg, px, headY, headR, c)
            nvgBeginPath(vg)
            nvgMoveTo(vg, px - halfWidth, bottomY)
            nvgLineTo(vg, px - halfWidth, shoulderY + halfWidth)
            nvgQuadTo(vg, px - halfWidth, shoulderY, px, shoulderY)
            nvgQuadTo(vg, px + halfWidth, shoulderY, px + halfWidth, shoulderY + halfWidth)
            nvgLineTo(vg, px + halfWidth, bottomY)
            nvgClosePath(vg)
            nvgFillColor(vg, Color(c))
            nvgFill(vg)
        end
    elseif self.kind == "settings" then
        for k = -1, 1 do
            local py = y + k * r * 0.8
            local px = x + (k == 0 and r * 0.4 or -r * 0.4)
            Line(vg, x - r, py, x + r, py, c, 1.5)
            Circle(vg, px, py, r * 0.23, W.Colors.card)
            Outline(vg, px - r * 0.23, py - r * 0.23, r * 0.46, r * 0.46, c, 1.4, r * 0.23)
        end
    elseif self.kind == "trends" then
        Line(vg, x - r, y - r, x - r, y + r, c, 1.5)
        Line(vg, x - r, y + r, x + r, y + r, c, 1.5)
        Line(vg, x - r * 0.7, y + r * 0.4, x, y - r * 0.3, c, 1.8)
        Line(vg, x, y - r * 0.3, x + r * 0.3, y, c, 1.8)
        Line(vg, x + r * 0.3, y, x + r, y - r * 0.8, c, 1.8)
    elseif self.kind == "pause" then
        Rect(vg, x - r * 0.65, y - r, r * 0.4, r * 2, c, 1)
        Rect(vg, x + r * 0.25, y - r, r * 0.4, r * 2, c, 1)
    elseif self.kind == "play" then
        nvgBeginPath(vg)
        nvgMoveTo(vg, x - r * 0.6, y - r)
        nvgLineTo(vg, x + r, y)
        nvgLineTo(vg, x - r * 0.6, y + r)
        nvgClosePath(vg); nvgFillColor(vg, Color(c)); nvgFill(vg)
    elseif self.kind == "speed" then
        nvgBeginPath(vg); nvgCircle(vg, x, y, r); nvgStroke(vg)
        Line(vg, x, y, x, y - r * 0.6, c, 1.6)
        Line(vg, x, y, x + r * 0.5, y + r * 0.2, c, 1.6)
    elseif self.kind == "help" then
        nvgBeginPath(vg); nvgCircle(vg, x, y, r); nvgStroke(vg)
        nvgFontFace(vg, "sans"); nvgFontSize(vg, size * 0.65)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, Color(c)); nvgText(vg, x, y, "?", nil)
    elseif self.kind == "restart" then
        -- 箭头尖沿圆弧切线朝右上；用实心箭头保持小尺寸下的方向清晰。
        local radius = size * 0.32
        local centerX, centerY = x + radius * 0.11, y - radius * 0.15
        local finish = math.pi * 1.25
        local tipX, tipY = centerX + math.cos(finish) * radius, centerY + math.sin(finish) * radius
        local tangentX, tangentY = -math.sin(finish), math.cos(finish)
        local backX, backY = tipX - tangentX * radius * 0.45, tipY - tangentY * radius * 0.45
        local wingX, wingY = -tangentY * radius * 0.27, tangentX * radius * 0.27
        nvgLineCap(vg, NVG_ROUND)
        nvgBeginPath(vg)
        nvgArc(vg, centerX, centerY, radius, -math.pi * 0.25, finish, NVG_CW)
        nvgStroke(vg)
        nvgBeginPath(vg)
        nvgMoveTo(vg, backX + wingX, backY + wingY)
        nvgLineTo(vg, tipX, tipY)
        nvgLineTo(vg, backX - wingX, backY - wingY)
        nvgClosePath(vg)
        nvgFillColor(vg, Color(c))
        nvgFill(vg)
    else
        local direction = self.kind == "foodDown" and -1 or 1
        Line(vg, x - r, y + r * direction, x + r, y - r * direction, c, 1.8)
        Line(vg, x + r, y - r * direction, x + r, y, c, 1.8)
        Line(vg, x + r, y - r * direction, x, y - r * direction, c, 1.8)
    end
    nvgRestore(vg)
end
W.Icon = Icon

---@class OriginMap : Widget
---@field ctx table
---@field clock number
---@field bounds table
---@field cameraInitialized boolean
---@field camera table
---@field pointers table<number, table>
---@field mouseX number
---@field mouseY number
local Map = UI.Widget:Extend("OriginMap")

function Map:Init(props)
    UI.Widget.Init(self, props)
    self.ctx = props.ctx
    self.clock = 0
    self.bounds = {x = 0, y = 0, cw = 0, ch = 0}
    self.camera = Camera.New()
    self.cameraInitialized = false
    self.pointers = {}
    self.mouseX, self.mouseY = 0, 0
end

function Map:Update(dt)
    if not Evolution.IsPaused(self.ctx) then self.clock = self.clock + dt end
    local l = self:GetAbsoluteLayout()
    if not self.cameraInitialized and l.w > 0 and l.h > 0 then self:FrameInitialView() end
end

function Map:FrameInitialView()
    self.camera = Camera.New()
    local fit = self:Geometry()
    -- 手机上先给出可辨认的局部视野；全图始终保留在 100%。
    self:SetZoom(math.max(1, math.min(2.5, 24 / fit.cw)))
end

function Map:Geometry()
    local config = self.ctx.world.config
    return Camera.Geometry(self.camera, self:GetAbsoluteLayout(), config.width, config.height)
end

function Map:SetZoom(zoom, x, y, dx, dy)
    self.cameraInitialized = true
    local config = self.ctx.world.config
    Camera.ZoomAt(self.camera, self:GetAbsoluteLayout(), config.width, config.height, zoom, x, y, dx, dy)
    if self.ctx.onZoomChanged then self.ctx.onZoomChanged() end
end

function Map:ResetCamera()
    self.cameraInitialized = true
    self.camera = Camera.New()
    self:CancelGesture()
    if self.ctx.onZoomChanged then self.ctx.onZoomChanged() end
end

function Map:CancelGesture()
    self.pointers = {}
end

function Map:Pick(x, y)
    if self.ctx.modalOpen then return end
    local l = self:GetAbsoluteLayout()
    if x < l.x or y < l.y or x > l.x + l.w or y > l.y + l.h then return end
    local b = self:Geometry()
    local world = self.ctx.world
    local cx, cy = math.floor((x - b.x) / b.cw) + 1, math.floor((y - b.y) / b.ch) + 1
    if cx < 1 or cy < 1 or cx > world.config.width or cy > world.config.height then return end
    self.ctx.selectCell(cx, cy)
end

-- 只追踪从地图开始的指针，滑块/面板上的第二根手指不会参与缩放。
-- 点击延迟到抬起；拖动、双指、取消事件都不会误选地块。
function Map:OnPointerDown(event)
    if self.ctx.modalOpen or not (event:IsTouch() or event:IsPrimaryButton()) then return end
    self.pointers[event.pointerId] = {x = event.x, y = event.y, startX = event.x, startY = event.y, moved = false}
    local count = 0
    for _ in pairs(self.pointers) do count = count + 1 end
    if count > 1 then for _, p in pairs(self.pointers) do p.moved = true end end
end

local function Pair(pointers)
    local ids = {}
    for id in pairs(pointers) do ids[#ids + 1] = id end
    table.sort(ids)
    if #ids < 2 then return nil end
    local a, b = pointers[ids[1]], pointers[ids[2]]
    return {x = (a.x + b.x) / 2, y = (a.y + b.y) / 2,
        distance = math.sqrt((a.x - b.x)^2 + (a.y - b.y)^2)}
end

function Map:OnPointerMove(event)
    self.mouseX, self.mouseY = event.x, event.y
    if self.ctx.modalOpen then self:CancelGesture(); return end
    local p = self.pointers[event.pointerId]
    if not p then return end
    local before = Pair(self.pointers)
    local dx, dy = event.x - p.x, event.y - p.y
    p.x, p.y = event.x, event.y
    local after = Pair(self.pointers)
    if before and after then
        if before.distance > 8 and after.distance > 8 then
            self:SetZoom(self.camera.zoom * after.distance / before.distance, before.x, before.y,
                after.x - before.x, after.y - before.y)
        end
        return
    end
    if not p.moved and (p.x - p.startX)^2 + (p.y - p.startY)^2 > 64 then
        p.moved = true
        dx, dy = p.x - p.startX, p.y - p.startY
    end
    if p.moved then
        local config = self.ctx.world.config
        Camera.Pan(self.camera, self:GetAbsoluteLayout(), config.width, config.height, dx, dy)
    end
end

function Map:OnPointerUp(event)
    local p = self.pointers[event.pointerId]
    self.pointers[event.pointerId] = nil
    if p and not p.moved and (event.x - p.startX)^2 + (event.y - p.startY)^2 <= 64 then
        self:Pick(event.x, event.y)
    end
end

function Map:OnPointerCancel(event)
    -- 取消一根手指时同时终止整个手势，剩余触点不能变成点击。
    self:CancelGesture()
end

function Map:OnWheel(dx, dy)
    if self.ctx.modalOpen then return end
    local l = self:GetAbsoluteLayout()
    local x, y = self.mouseX, self.mouseY
    if x < l.x or x > l.x + l.w or y < l.y or y > l.y + l.h then
        x, y = l.x + l.w / 2, l.y + l.h / 2
    end
    self:SetZoom(self.camera.zoom * 1.15 ^ math.max(-4, math.min(4, dy)), x, y)
end

local function House(vg, x, y, size, variant, quality)
    local w, h = size * 0.22, size * 0.21
    Rect(vg, x, y, w, h, {235, 225, 189, 255})
    nvgBeginPath(vg)
    nvgMoveTo(vg, x - size * 0.025, y + size * 0.025)
    nvgLineTo(vg, x + w / 2, y - h * 0.65)
    nvgLineTo(vg, x + w + size * 0.025, y + size * 0.025)
    nvgClosePath(vg)
    nvgFillColor(vg, Color(variant == "explore" and {75, 133, 119, 255} or {136, 116, 79, 255}))
    nvgFill(vg)
    Rect(vg, x + w * 0.42, y + h * 0.4, w * 0.2, h * 0.6, {98, 96, 72, 255})
    if quality > 0.7 then
        Rect(vg, x + w * 0.13, y + h * 0.3, math.max(1, w * 0.18), math.max(1, h * 0.25), {255, 232, 141, 255})
    end
end


function Map:Render(vg)
    local ctx, b = self.ctx, self:Geometry()
    local world = ctx.world
    local regionIds = world.cellRegionIds or {}
    local regions = world.regions or {}
    local selectedRegionId = regionIds[ctx.selectedIndex]
    self.bounds = b
    local l = self:GetAbsoluteLayout()
    local detail = Camera.Detail(b.cw)
    local cellLayout = CellVisuals.Layout(b.cw, b.ch)
    Rect(vg, l.x, l.y, l.w, l.h, {232, 234, 219, 255}, 12)
    nvgSave(vg)
    nvgIntersectScissor(vg, l.x + 1, l.y + 1, l.w - 2, l.h - 2)
    -- 地图坐标刻度是几何图形，数值标签由周边 UI 负责。
    for x = 0, world.config.width do
        Line(vg, b.x + x * b.cw, b.y - 6, b.x + x * b.cw, b.y - (x % 4 == 0 and 12 or 9), {162, 172, 148, 160}, 1)
    end
    for y = 0, world.config.height do
        Line(vg, b.x - 7, b.y + y * b.ch, b.x - (y % 4 == 0 and 13 or 10), b.y + y * b.ch, {162, 172, 148, 160}, 1)
    end
    Rect(vg, b.x - 4, b.y - 4, b.w + 8, b.h + 8, {173, 186, 153, 255}, 3)
    for i, cell in ipairs(world.cells) do
        local metric = world.metrics[i]
        local x, y = b.x + (cell.x - 1) * b.cw, b.y + (cell.y - 1) * b.ch
        if x + b.cw >= l.x and x <= l.x + l.w and y + b.ch >= l.y and y <= l.y + l.h then
            local quality = metric.craftPerCapita / (world.config.prosperousCraftMultiplier * world.baselineCraft)
            local shade = ((i * 29 + world.seed * 7) % 13) / 13
            local fill
            if ctx.layer == "terrain" then
                fill = {190, 201, 164, 255}
            elseif ctx.layer == "institution" then
                fill = cell.institution == "explore" and Mix({90, 159, 143}, {135, 191, 164}, shade * 0.6)
                    or Mix({194, 177, 136}, {210, 194, 152}, shade * 0.6)
            elseif ctx.layer == "population" then
                fill = Mix({226, 229, 202}, {99, 131, 76}, cell.population / 65)
            else
                fill = Mix({151, 167, 122}, {206, 214, 141}, (quality - 0.4) * 1.15 + shade * 0.15)
            end
            Rect(vg, x, y, b.cw, b.ch, fill)
        end
    end
    -- 先完成整张底图，再统一画地貌；后面的格子不能盖住前面的山脉。
    TerrainBackdrop.Draw(vg, world, b, ctx.layer)
    -- 分割线独立于地区标注，由“地块分界”开关控制，随相机对齐每个地块。
    if ctx.showGrid == true then
        nvgBeginPath(vg)
        for column = 0, world.config.width do
            local gx = b.x + column * b.cw
            nvgMoveTo(vg, gx, b.y); nvgLineTo(vg, gx, b.y + b.h)
        end
        for row = 0, world.config.height do
            local gy = b.y + row * b.ch
            nvgMoveTo(vg, b.x, gy); nvgLineTo(vg, b.x + b.w, gy)
        end
        nvgStrokeColor(vg, nvgRGBA(208, 208, 205, 230))
        nvgStrokeWidth(vg, 1.6)
        nvgStroke(vg)
    end
    for i, cell in ipairs(world.cells) do
        local metric = world.metrics[i]
        local x, y = b.x + (cell.x - 1) * b.cw, b.y + (cell.y - 1) * b.ch
        if x + b.cw >= l.x and x <= l.x + l.w and y + b.ch >= l.y and y <= l.y + l.h then
            local quality = metric.craftPerCapita / (world.config.prosperousCraftMultiplier * world.baselineCraft)
            if detail >= 2 then
                local state = CellVisuals.State(cell.population, metric.foodRatio, metric.craftPerCapita, world.baselineCraft)
                for k = 1, state.foodBlocks do
                    local block = assert(cellLayout.food[k])
                    Rect(vg, x + block.x, y + block.y, block.width, block.height, state.foodColor)
                end
                for k = 1, state.houses do
                    local house = assert(cellLayout.houses[k])
                    House(vg, x + house.x, y + house.y, house.size, cell.institution, quality)
                end
                for k = 1, state.roses do
                    local rose = assert(cellLayout.roses[k])
                    Rose(vg, x + rose.x, y + rose.y, rose.size)
                end
            end
            if metric.foodRatio >= 1 and quality >= 1 then
                Circle(vg, x + b.cw * 0.7, y + b.ch * 0.5, b.cw * 0.17, {255, 232, 126, 85})
                Circle(vg, x + b.cw * 0.7, y + b.ch * 0.5, b.cw * 0.06, {255, 237, 169, 255})
            end
            if b.cw >= 60 then
                nvgFontFace(vg, UI.Theme.FontFace("sans", "normal"))
                nvgFontSize(vg, math.min(12, b.cw * 0.14))
                nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_TOP)
                nvgFillColor(vg, Color(W.Colors.ink))
                nvgText(vg, x + b.cw * 0.94, y + b.ch * 0.015, string.format("%.0f户", cell.population))
            end
            if cell.protectionTicks > 0 then
                Outline(vg, x + 1.4, y + 1.4, b.cw - 2.8, b.ch - 2.8, {232, 198, 98, 230}, 1.4, 1)
            end
        end
    end
    if ctx.showRegions ~= false then
        -- 地区边界用深色外沿与地区色细线，确保在农田和山地上都能辨认。
        for i, cell in ipairs(world.cells) do
            local region = regions[regionIds[i]]
            if region then
                local x, y = b.x + (cell.x - 1) * b.cw, b.y + (cell.y - 1) * b.ch
                if x + b.cw >= l.x and x <= l.x + l.w and y + b.ch >= l.y and y <= l.y + l.h then
                    local function Border(x1, y1, x2, y2, neighborId)
                        local owner = neighborId == selectedRegionId and regions[neighborId] or region
                        local selected = owner.id == selectedRegionId
                        local c = {owner.color[1], owner.color[2], owner.color[3], selected and 245 or 220}
                        Line(vg, x1, y1, x2, y2, {25, 35, 29, selected and 220 or 185}, selected and 4.0 or 3.2)
                        Line(vg, x1, y1, x2, y2, c, selected and 2.0 or 1.4)
                    end
                    -- 共享边只由右侧/下侧格子画一次；任意一侧选中都优先采用选中色。
                    if cell.x == 1 or regionIds[i - 1] ~= region.id then
                        Border(x, y, x, y + b.ch, cell.x > 1 and regionIds[i - 1] or 0)
                    end
                    if cell.y == 1 or regionIds[i - world.width] ~= region.id then
                        Border(x, y, x + b.cw, y, cell.y > 1 and regionIds[i - world.width] or 0)
                    end
                    if cell.x == world.width then Border(x + b.cw, y, x + b.cw, y + b.ch, 0) end
                    if cell.y == world.height then Border(x, y + b.ch, x + b.cw, y + b.ch, 0) end
                end
            end
        end
    end
    -- 勾选显示全图，取消勾选保留选中地块的传入与传出；全图缩放也能观察。
    local flowReport = ctx.phase == "simulation" and ctx.pendingGeneration and ctx.pendingGeneration.lastReport
    local arrows = flowReport and TechnologyVisuals.Arrows(world, b, l, ctx.showTechnology, ctx.selectedIndex, flowReport) or {}
    for _, arrow in ipairs(arrows) do
        local moving = TechnologyVisuals.Moving(arrow, ctx.accumulator, Evolution.GenerationSeconds)
        if moving then
            local function Path(points)
                nvgBeginPath(vg)
                for i, p in ipairs(points) do
                    if i == 1 then nvgMoveTo(vg, p[1], p[2]) else nvgLineTo(vg, p[1], p[2]) end
                end
                nvgClosePath(vg)
            end
            local c = arrow.color
            local function Fill()
                if moving.gradient then
                    local edge = moving.gradient
                    nvgFillPaint(vg, nvgLinearGradient(vg, edge.x1, edge.y1, edge.x2, edge.y2,
                        nvgRGBA(c[1], c[2], c[3], 0), Color(c)))
                else
                    nvgFillColor(vg, Color(c))
                end
                nvgFill(vg)
            end
            if moving.tail then
                local tail = moving.tail
                Path(tail.points)
                Fill()
            end
            Path(moving.points)
            Fill()
        end
    end
    -- 暖金色光点与蓝色技术流区分；微小的真实流量也保持可见，全图视角不隐藏。
    local migration = flowReport and Evolution.Migration(ctx.accumulator, Evolution.GenerationSeconds)
    if migration and ctx.showMigration then
        for _, flow in ipairs(flowReport.flows) do
            local source, target = world.cells[flow.from], world.cells[flow.to]
            local t, alpha = migration.position, migration.alpha
            local sx, sy = b.x + (source.x - 0.5) * b.cw, b.y + (source.y - 0.5) * b.ch
            local tx, ty = b.x + (target.x - 0.5) * b.cw, b.y + (target.y - 0.5) * b.ch
            local strength = flow.amount / (flow.amount + 0.12)
            local radius = math.min(4.0, math.max(1.65, math.min(b.cw, b.ch) * 0.047) + strength * 1.1)
            local px, py = sx + (tx - sx) * t, sy + (ty - sy) * t
            local halo = radius * 2.8
            if px + halo >= l.x and px - halo <= l.x + l.w and py + halo >= l.y and py - halo <= l.y + l.h then
                local distance = math.sqrt((tx - sx)^2 + (ty - sy)^2)
                for j = 2, 1, -1 do
                    local trail = t - j * radius * 2.1 / distance
                    if trail >= 0 then
                        Circle(vg, sx + (tx - sx) * trail, sy + (ty - sy) * trail,
                            radius * (j == 1 and 0.52 or 0.32), {255, 212, 92, (j == 1 and 150 or 75) * alpha})
                    end
                end
                nvgBeginPath(vg)
                nvgCircle(vg, px, py, halo)
                nvgFillPaint(vg, nvgRadialGradient(vg, px, py, radius * 0.45, halo,
                    nvgRGBA(255, 215, 103, (125 + strength * 45) * alpha), nvgRGBA(255, 215, 103, 0)))
                nvgFill(vg)
                Circle(vg, px, py, radius + 0.45, {124, 85, 28, 210 * alpha})
                Circle(vg, px, py, radius, {255, 213, 99, 255 * alpha})
                Circle(vg, px, py, radius * 0.62, {255, 255, 231, 255 * alpha})
            end
        end
    end
    if world.lastReport and ctx.showMigration then
        if detail >= 2 and ctx.tickAge < 1.0 then
            for _, change in ipairs(world.lastReport.changes) do
                local cell = world.cells[change.index]
                Outline(vg, b.x + (cell.x - 1) * b.cw + 1, b.y + (cell.y - 1) * b.ch + 1,
                    b.cw - 2, b.ch - 2, {243, 229, 145, 200 * (1 - ctx.tickAge)}, 2)
            end
        end
    end
    if ctx.showRegions ~= false then
        for _, label in ipairs(RegionLayout.Labels(world, b, l, selectedRegionId)) do
            nvgFontFace(vg, UI.Theme.FontFace("sans", "normal"))
            nvgFontSize(vg, label.fontSize)
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            local tx, ty = label.x + label.w / 2, label.y + label.h / 2
            -- 白色字芯与黑边先合成，再整体混合一次。不能把半透明白字叠在黑字上。
            local entry = RegionLabelAtlas.labels[label.region.name]
            local image = regionLabelImages[vg]
            if image == nil then
                image = nvgCreateImage(vg, "Textures/region-labels.png", 0)
                regionLabelImages[vg] = image
            end
            if entry and image > 0 then
                local labelScale = label.fontSize / 48
                nvgBeginPath(vg)
                nvgRect(vg, label.x, label.y, label.w, label.h)
                nvgFillPaint(vg, nvgImagePattern(vg, label.x, label.y - entry.y * labelScale,
                    RegionLabelAtlas.width * labelScale, RegionLabelAtlas.height * labelScale, 0, image, 0.3))
                nvgFill(vg)
            else
                -- 未知名称或资源不可用时仍保留透明白字，避免重新引入叠黑的问题。
                nvgFillColor(vg, nvgRGBA(255, 255, 255, 77))
                nvgText(vg, tx, ty, label.region.name)
            end
        end
    end
    local sx, sy = b.x + (ctx.regionX - 1) * b.cw, b.y + (ctx.regionY - 1) * b.ch
    local rw, rh = world.config.regionSize * b.cw, world.config.regionSize * b.ch
    -- 行动框内每个格子都接受干预。
    for cy = ctx.regionY, ctx.regionY + world.config.regionSize - 1 do
        for cx = ctx.regionX, ctx.regionX + world.config.regionSize - 1 do
            Rect(vg, b.x + (cx - 1) * b.cw, b.y + (cy - 1) * b.ch, b.cw, b.ch, {255, 246, 189, 32})
        end
    end
    Outline(vg, sx - 1, sy - 1, rw + 2, rh + 2, {255, 254, 231, 255}, 3, 3)
    Outline(vg, sx - 2.5, sy - 2.5, rw + 5, rh + 5, W.Colors.green, 1, 3)
    for _, dx in ipairs({0, rw}) do
        for _, dy in ipairs({0, rh}) do
            Circle(vg, sx + dx, sy + dy, 2.7, W.Colors.green)
        end
    end
    local selected = world.cells[ctx.selectedIndex]
    Outline(vg, b.x + (selected.x - 1) * b.cw + 2, b.y + (selected.y - 1) * b.ch + 2,
        b.cw - 4, b.ch - 4, {253, 255, 235, 225}, 1, 1)
    nvgRestore(vg)
end
W.Map = Map

---@class OriginChart : Widget
---@field ctx table
---@field metric string
---@field color table
local Chart = UI.Widget:Extend("OriginChart")
function Chart:Init(props)
    UI.Widget.Init(self, props)
    self.ctx = props.ctx
    self.metric = props.metric or "craftPerCapita"
    self.color = props.color or W.Colors.green
end

function Chart:Render(vg)
    local l = self:GetAbsoluteLayout()
    local history, baseline = self.ctx.world.history, self.ctx.baseline
    local lo, hi = math.huge, 0
    for _, item in ipairs(history) do
        local point = item.summary or item
        lo = math.min(lo, point[self.metric] or 0)
        hi = math.max(hi, point[self.metric] or 0)
    end
    if baseline then
        for _, item in ipairs(baseline) do
            local point = item.summary or item
            lo = math.min(lo, point[self.metric] or 0)
            hi = math.max(hi, point[self.metric] or 0)
        end
    end
    if self.metric == "prosperousShare" or self.metric == "exploreShare" then lo, hi = 0, 1 end
    if hi - lo < 0.001 then hi = lo + 1 end
    local range = hi - lo
    local px, py, pw, ph = l.x + 2, l.y + 5, l.w - 4, l.h - 10
    for k = 0, 2 do
        Line(vg, px, py + ph * k / 2, px + pw, py + ph * k / 2, {210, 216, 200, 155}, 0.7)
    end
    if self.metric == "prosperousShare" then
        local goalY = py + ph * 0.2
        for x = px, px + pw - 4, 8 do Line(vg, x, goalY, x + 4, goalY, {187, 149, 68, 170}, 0.8) end
    end
    local function Point(index, value)
        return px + ((index - 1) / (self.ctx.world.config.rounds * self.ctx.world.config.generationsPerRound)) * pw,
            py + ph - math.max(0, math.min(1, (value - lo) / range)) * ph
    end
    if baseline then
        nvgBeginPath(vg)
        for i, item in ipairs(baseline) do
            local point = item.summary or item
            local x, y = Point(i, point[self.metric] or 0)
            if i == 1 then nvgMoveTo(vg, x, y) else nvgLineTo(vg, x, y) end
        end
        nvgStrokeColor(vg, nvgRGBA(154, 164, 145, 135))
        nvgStrokeWidth(vg, 1.2)
        nvgStroke(vg)
    end
    if #history > 1 then
        nvgBeginPath(vg)
        for i, item in ipairs(history) do
            local point = item.summary or item
            local x, y = Point(i, point[self.metric] or 0)
            if i == 1 then nvgMoveTo(vg, x, y) else nvgLineTo(vg, x, y) end
        end
        local last = history[#history].summary or history[#history]
        local lx, ly = Point(#history, last[self.metric] or 0)
        nvgLineTo(vg, lx, py + ph)
        nvgLineTo(vg, px, py + ph)
        nvgClosePath(vg)
        nvgFillPaint(vg, nvgLinearGradient(vg, px, py, px, py + ph, Color(self.color, 45), Color(self.color, 2)))
        nvgFill(vg)
        nvgBeginPath(vg)
        for i, item in ipairs(history) do
            local point = item.summary or item
            local x, y = Point(i, point[self.metric] or 0)
            if i == 1 then nvgMoveTo(vg, x, y) else nvgLineTo(vg, x, y) end
        end
        nvgStrokeColor(vg, Color(self.color))
        nvgStrokeWidth(vg, 1.8)
        nvgStroke(vg)
        Circle(vg, lx, ly, 2.7, self.color)
    else
        local point = history[1].summary or history[1]
        local x, y = Point(1, point[self.metric] or 0)
        Circle(vg, x, y, 2.7, self.color)
    end
end
W.Chart = Chart

-- 复用 UI 的坐标、字体与渲染帧，不另开 NanoVG 帧。
---@class OriginPopulationCurve : Widget
---@field config OriginParameters
local PopulationCurve = UI.Widget:Extend("OriginPopulationCurve")
function PopulationCurve:Init(props)
    UI.Widget.Init(self, props)
    self.config = props.config
end
function PopulationCurve:Render(vg)
    local S = require("OriginSimulation")
    local l, cfg = self:GetAbsoluteLayout(), self.config
    local x, y, w, h = l.x + 40, l.y + 20, math.max(1, l.w - 54), math.max(1, l.h - 50)
    -- 固定纵轴 ±100%，上限改变时振幅变化可见，不自动缩放掩盖变化。
    nvgSave(vg)
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 9)
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    for i = -1, 1 do
        local py = y + h * (1 - i) / 2
        Line(vg, x, py, x + w, py, W.Colors.line, 1)
        nvgFillColor(vg, Color(W.Colors.muted))
        nvgText(vg, l.x, py, string.format("%+d%%", i * 100))
    end
    for i = 0, 2 do
        local px = x + w * i / 2
        Line(vg, px, y, px, y + h, W.Colors.line, 1)
        nvgFillColor(vg, Color(W.Colors.muted))
        nvgText(vg, px - 3, y + h + 12, tostring(i))
    end
    for _, sign in ipairs({-1, 1}) do
        local py = y + h * (1 - sign * cfg.naturalGrowthRate) / 2
        for px = x, x + w - 3, 7 do Line(vg, px, py, math.min(px + 3, x + w), py, W.Colors.gold, 1) end
    end
    nvgBeginPath(vg)
    for i = 0, 100 do
        local ratio = i / 50
        local px = x + w * i / 100
        local py = y + h * (1 - S.PopulationChangeRate(ratio, cfg)) / 2
        if i == 0 then nvgMoveTo(vg, px, py) else nvgLineTo(vg, px, py) end
    end
    nvgStrokeColor(vg, Color(W.Colors.green))
    nvgStrokeWidth(vg, 2)
    nvgStroke(vg)
    nvgFillColor(vg, Color(W.Colors.muted))
    nvgText(vg, x, l.y + 7, "人口净变化 / 世代")
    nvgText(vg, x, y + h + 27, "温饱比 s（1 = 刚好够吃）")
    nvgRestore(vg)
end
W.PopulationCurve = PopulationCurve
return W
