-- 独立本地视觉验收入口；正式 main.lua 不加载。截图来自真实 backbuffer。
require("main")
local GameStart = Start
local UI = require("urhox-libs/UI")
local View = require("OriginView")
local frame, stopped = 0, false

local function Screenshot(name)
    local image = Image()
    assert(graphics:TakeScreenShot(image), "无法读取 backbuffer")
    assert(image:SavePNG("terrain-backdrop-" .. name .. ".png"), "截图保存失败")
    print("[地形底图截图] " .. name .. " " .. image.width .. "x" .. image.height)
end

local function Map()
    return assert(OriginDebug.GetGame().root:FindById("worldMap")) --[[@as OriginMap]]
end

local function Detail()
    local ctx = OriginDebug.GetGame()
    local world = ctx.world
    local selected = 1
    -- 选一块靠近丘陵的山地，同时查看地貌过渡和房屋、数值。
    for i, cell in ipairs(world.cells) do
        if cell.terrainKind == "mountain" then
            selected = i
            local touchesHill = false
            for _, j in ipairs(assert(world.neighbors[i])) do
                if world.cells[j].terrainKind == "hill" then touchesHill = true end
            end
            if touchesHill and cell.x > 3 and cell.y > 3 then break end
        end
    end
    local cell = world.cells[selected]
    OriginDebug.Select(cell.x, cell.y)
    local map = Map()
    map:SetZoom(3.2)
    map.camera.centerX = (cell.x - 0.5) / world.config.width
    map.camera.centerY = (cell.y - 0.5) / world.config.height
end

local steps = {
    [20] = function() Screenshot("default") end,
    [30] = function() Map():SetZoom(1) end,
    [40] = function() Screenshot("overview") end,
    [50] = Detail,
    [60] = function() Screenshot("detail") end,
    [70] = function() local ctx = OriginDebug.GetGame(); ctx.layer = "population"; View.Refresh(ctx) end,
    [80] = function() Screenshot("population") end,
    [90] = function() local ctx = OriginDebug.GetGame(); ctx.layer = "institution"; View.Refresh(ctx) end,
    [100] = function() Screenshot("institution") end,
    [110] = function() OriginDebug.Restart(); UI.Layout() end,
    [120] = function() Screenshot("restored"); print("[地形底图验收完成] 六张真实截图；须读取像素后判断视觉"); stopped = true end,
}

function Start()
    GameStart()
    SubscribeToEvent("Update", "OriginTerrainBackdropAcceptanceUpdate")
end

function OriginTerrainBackdropAcceptanceUpdate()
    if stopped then return end
    frame = frame + 1
    if not steps[frame] then return end
    local ok, failure = pcall(steps[frame])
    if not ok then stopped = true; print("[地形底图验收失败] " .. tostring(failure)) end
end
