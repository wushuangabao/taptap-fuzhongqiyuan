-- 独立真实窗口验收入口；正式 main.lua 不加载。
require("main")
local GameStart = Start
local UI = require("urhox-libs/UI")
local frame, done = 0, false

local function Screenshot(name)
    local image = Image()
    assert(graphics:TakeScreenShot(image))
    assert(image:SavePNG("single-cell-" .. name .. ".png"))
end

local function Click(ctx, id)
    UI.Layout()
    local widget = assert(ctx.root:FindById(id))
    local box, scale = widget:GetAbsoluteLayoutForHitTest(), UI.GetScale()
    local data = {pointerId = 0, pointerType = "mouse", button = MOUSEB_LEFT,
        x = (box.x + box.w / 2) * scale, y = (box.y + box.h / 2) * scale}
    UI.HandlePointerDown(UI.PointerEvent.new("PointerDown", data))
    UI.HandlePointerUp(UI.PointerEvent.new("PointerUp", data))
end

function Start()
    GameStart()
    UnsubscribeFromEvent("Update")
    OriginDebug.ClosePanel()
    OriginDebug.GetGame().tipsClosed = true
    SubscribeToEvent("Update", "SingleCellAcceptanceUpdate")
end

function SingleCellAcceptanceUpdate()
    if done then return end
    frame = frame + 1
    local ctx = OriginDebug.GetGame()
    if frame == 10 then
        UI.Layout()
        local map = assert(ctx.root:FindById("worldMap")) --[[@as OriginMap]]
        map:SetZoom(1)
        local b, scale = map:Geometry(), UI.GetScale()
        local data = {pointerId = 0, pointerType = "mouse", button = MOUSEB_LEFT,
            x = (b.x + 23.5 * b.cw) * scale, y = (b.y + 15.5 * b.ch) * scale}
        UI.HandlePointerDown(UI.PointerEvent.new("PointerDown", data))
        UI.HandlePointerUp(UI.PointerEvent.new("PointerUp", data))
        assert(ctx.selectedIndex == 384 and ctx.regionX == 24 and ctx.regionY == 16)
        assert(ctx.root:FindById("roundLabel"):GetText() == "第 1 / 50 轮")
        print("[单格验收] 真实指针选择边角单格，界面显示50轮")
    elseif frame == 15 then
        Screenshot("selection")
        local before, neighbor = ctx.world.cells[384].craft, ctx.world.cells[383].craft
        Click(ctx, "action_craft"); Click(ctx, "action_protect"); Click(ctx, "confirm")
        assert(ctx.phase == "simulation" and ctx.ticksRemaining == 5)
        assert(ctx.world.actions[1].action == "protect" and ctx.world.cells[384].craft == before)
        assert(ctx.world.cells[383].craft == neighbor and ctx.world.cells[383].protectionTicks == 0)
        assert(ctx.world.cells[384].protectionTicks == 5)
        OriginDebug.Confirm(); assert(ctx.world.round == 1)
    elseif frame > 15 then
        if ctx.phase == "simulation" then
            OriginDebug.Advance()
            if ctx.world.generation == 5 then
                assert(ctx.phase == "decision" and ctx.world.cells[384].protectionTicks == 0)
                print("[单格验收] 只干预一格，五世代后回到决策，保护到期")
            end
        elseif ctx.phase == "decision" then
            OriginDebug.Select(1, 1); OriginDebug.Choose("craft"); OriginDebug.Confirm()
        else
            assert(ctx.phase == "ended" and ctx.world.round == 50 and ctx.world.generation == 250)
            assert(#ctx.world.actions == 50 and #ctx.world.history == 251)
            OriginDebug.Confirm(); assert(ctx.world.round == 50)
            Screenshot("ending")
            print("[单格验收完成] 50轮/250世代结算，第51次确认无效")
            done = true
        end
    end
end
