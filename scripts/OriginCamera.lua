-- 地图相机只处理基准像素；不改变世界数据，也不重复应用 DPR。
local Camera = {}
Camera.MIN_ZOOM, Camera.MAX_ZOOM = 1, 6

local function Clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end

function Camera.New()
    return {zoom = 1, centerX = 0.5, centerY = 0.5}
end

function Camera.Geometry(camera, viewport, columns, rows)
    local cw = math.max(1, math.min((viewport.w - 32) / columns, (viewport.h - 32) / rows * 1.18)) * camera.zoom
    local ch = cw / 1.18
    local w, h = cw * columns, ch * rows
    -- 小于视口的轴始终居中；放大后边缘不能拖离视口，避免地图丢失。
    camera.centerX = w <= viewport.w and 0.5 or Clamp(camera.centerX, viewport.w / (2 * w), 1 - viewport.w / (2 * w))
    camera.centerY = h <= viewport.h and 0.5 or Clamp(camera.centerY, viewport.h / (2 * h), 1 - viewport.h / (2 * h))
    return {x = viewport.x + viewport.w / 2 - camera.centerX * w,
        y = viewport.y + viewport.h / 2 - camera.centerY * h, w = w, h = h, cw = cw, ch = ch}
end

function Camera.ZoomAt(camera, viewport, columns, rows, zoom, x, y, dx, dy)
    local before = Camera.Geometry(camera, viewport, columns, rows)
    x, y = x or (viewport.x + viewport.w / 2), y or (viewport.y + viewport.h / 2)
    local u, v = (x - before.x) / before.w, (y - before.y) / before.h
    camera.zoom = Clamp(zoom, Camera.MIN_ZOOM, Camera.MAX_ZOOM)
    local after = Camera.Geometry(camera, viewport, columns, rows)
    camera.centerX = u - (x + (dx or 0) - viewport.x - viewport.w / 2) / after.w
    camera.centerY = v - (y + (dy or 0) - viewport.y - viewport.h / 2) / after.h
    return Camera.Geometry(camera, viewport, columns, rows)
end

function Camera.Pan(camera, viewport, columns, rows, dx, dy)
    local b = Camera.Geometry(camera, viewport, columns, rows)
    camera.centerX, camera.centerY = camera.centerX - dx / b.w, camera.centerY - dy / b.h
    return Camera.Geometry(camera, viewport, columns, rows)
end

function Camera.Detail(cw)
    if cw < 22 then return 1 end
    if cw < 42 then return 2 end
    return 3
end

return Camera
