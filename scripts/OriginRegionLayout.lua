-- 地区名称的地图标注布局。只读取地图几何，不改变镜头或模拟状态。
local Layout = {}

---@param world OriginWorld
---@param geometry table
---@param viewport table
---@param selectedId integer?
---@return table[]
function Layout.Labels(world, geometry, viewport, selectedId)
    local labels, ordered = {}, {}
    local regions = world.regions or {}
    if selectedId and regions[selectedId] then ordered[#ordered + 1] = regions[selectedId] end
    for _, region in ipairs(regions) do
        if region.id ~= selectedId then ordered[#ordered + 1] = region end
    end
    for _, region in ipairs(ordered) do
        -- 地名随地图地块缩小，正常视角最多48；文字图片与碰撞范围使用相同比例。
        local fontSize = math.min(48, geometry.ch * 1.25)
        local scale = fontSize / 48
        -- 碰撞范围仅覆盖文字与描边，不再为底牌预留宽边距。
        local w, h = ((utf8.len(region.name) or #region.name) * 48 + 4) * scale, 54 * scale
        local x = geometry.x + (region.anchorX - 0.5) * geometry.cw - w / 2
        local y = geometry.y + (region.anchorY - 0.5) * geometry.ch - h / 2
        -- 不把屏幕外的地名挪到边缘，以免误标到别的地区。
        local visible = region.hasHabitableLand ~= false and x >= viewport.x + 3 and x + w <= viewport.x + viewport.w - 3
            and y >= viewport.y + 3 and y + h <= viewport.y + viewport.h - 3
        for _, placed in ipairs(labels) do
            if x < placed.x + placed.w + 4 and x + w + 4 > placed.x
                and y < placed.y + placed.h + 4 and y + h + 4 > placed.y then visible = false end
        end
        if visible then
            labels[#labels + 1] = {x = x, y = y, w = w, h = h, fontSize = fontSize,
                region = region, selected = region.id == selectedId}
        end
    end
    return labels
end

return Layout
