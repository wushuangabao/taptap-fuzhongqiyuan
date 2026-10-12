-- 共用悬浮说明：鼠标停留 / 手指长按，浮层不参与布局或命中测试。
local UI = require("urhox-libs/UI")
local C = require("OriginWidgets").Colors
---@class OriginTips
---@field ctx table
---@field elapsed number
---@field active table|false
---@field popup Panel|false
local Tips = {}
Tips.__index = Tips

---@return OriginTips
function Tips.New(ctx)
    return setmetatable({ctx = ctx, elapsed = 0, active = false, popup = false}, Tips)
end

function Tips:Hide()
    if self.popup then self.popup:Destroy() end
    self.popup, self.active, self.elapsed = false, false, 0
end

function Tips:Begin(widget, text, touch, event, allowModal)
    self:Hide()
    self.active = {widget = widget, text = text, touch = touch, x = event.x, y = event.y, allowModal = allowModal}
end

function Tips:Update(dt)
    local active = self.active
    if not active then return end
    if (self.ctx.modalOpen and not active.allowModal) or self.ctx.portraitBlocked then self:Hide(); return end
    if self.popup then self:PositionPopup(); return end
    self.elapsed = self.elapsed + dt
    if self.elapsed < (active.touch and 0.55 or 0.35) then return end
    local message = type(active.text) == "function" and active.text() or active.text
    if not message or message == "" then return end
    if active.touch then active.widget.tipSuppressClick = true end
    local shell = self.ctx.root:FindById("shell"):GetAbsoluteLayout()
    local width = math.min(280, shell.w)
    local popup = UI.Panel {id = "buttonTip", position = "absolute", width = width, padding = 12,
        backgroundColor = {35, 56, 45, 250}, borderRadius = 9, pointerEvents = "none", children = {
            UI.Label {text = message, fontFamily = "sans", fontSize = 11, fontColor = C.card,
                width = "100%", whiteSpace = "normal", pointerEvents = "none"},
        }}
    self.ctx.root:AddChild(popup)
    self.popup = popup
    self:PositionPopup()
end

function Tips:PositionPopup()
    -- Label 在渲染时才更新多行高度；后续帧须按真实高度重新避让屏幕边缘。
    local popup, active = self.popup, self.active
    if not popup or not active then return end
    if UI.IsLayoutDirty() then UI.Layout() end
    local shell = self.ctx.root:FindById("shell"):GetAbsoluteLayout()
    -- 提示挂在根节点，锚点要扣除 ScrollView 的滚动偏移。
    local anchor = active.widget:GetAbsoluteLayoutForHitTest()
    local bounds = popup:GetAbsoluteLayout()
    local width, height = bounds.w, bounds.h
    local x = math.max(shell.x, math.min(shell.x + shell.w - width, anchor.x + anchor.w / 2 - width / 2))
    local y = anchor.y + anchor.h + 8
    if y + height > shell.y + shell.h then y = anchor.y - height - 8 end
    y = math.max(shell.y, math.min(shell.y + shell.h - height, y))
    if popup.props.left ~= x or popup.props.top ~= y then
        popup:SetStyle({left = x, top = y})
    end
end

function Tips:Attach(widget, text, allowModal)
    local manager = self
    local enter, leave = widget.OnPointerEnter, widget.OnPointerLeave
    local down, move = widget.OnPointerDown, widget.OnPointerMove
    local up, cancel, click = widget.OnPointerUp, widget.OnPointerCancel, widget.OnClick
    widget.OnPointerEnter = function(w, event)
        enter(w, event)
        if event:IsMouse() then manager:Begin(w, text, false, event, allowModal) end
    end
    widget.OnPointerLeave = function(w, event)
        leave(w, event)
        if manager.active and manager.active.widget == w then manager:Hide() end
    end
    widget.OnPointerDown = function(w, event)
        w.tipSuppressClick = false
        manager:Hide()
        if event:IsTouch() then manager:Begin(w, text, true, event, allowModal) end
        down(w, event)
    end
    widget.OnPointerMove = function(w, event)
        local active = manager.active
        if active and active.widget == w and active.touch and
            ((event.x - active.x)^2 + (event.y - active.y)^2 > 64) then
            w.tipSuppressClick = true
            manager:Hide()
        end
        move(w, event)
    end
    widget.OnPointerUp = function(w, event)
        if manager.active and manager.active.widget == w and manager.active.touch then manager:Hide() end
        up(w, event)
    end
    widget.OnPointerCancel = function(w, event)
        manager:Hide()
        w.tipSuppressClick = true
        cancel(w, event)
    end
    widget.OnClick = function(w, event)
        manager:Hide()
        if w.tipSuppressClick then w.tipSuppressClick = false; return end
        click(w, event)
    end
    return widget
end

return Tips
