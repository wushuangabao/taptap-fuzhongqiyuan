-- 游戏通知使用可换行 Label；内置 Toast 的固定单行绘制会裁掉长中文。
local UI = require("urhox-libs/UI")
local C = require("OriginWidgets").Colors
local Notifications = {}
Notifications.__index = Notifications

function Notifications.New(root)
    local self = setmetatable({}, Notifications)
    self:Init(root)
    return self
end

function Notifications:Init(root)
    ---@type table[]
    self.items = {}
    self.stack = UI.Column {id = "notificationStack", width = 520, maxWidth = "100%",
        gap = 8, pointerEvents = "box-none"}
    self.layer = UI.SafeAreaView {id = "notifications", position = "absolute",
        left = 0, top = 0, width = "100%", height = "100%", nativeMenuInset = true,
        pointerEvents = "box-none", children = {
            UI.Column {width = "100%", height = "100%", padding = 20,
                alignItems = "flex-end", pointerEvents = "box-none", children = {self.stack}},
        }}
    root:AddChild(self.layer)
end

function Notifications:Dismiss(item)
    for i, current in ipairs(self.items) do
        if current == item then
            current.panel:Destroy()
            table.remove(self.items, i)
            return
        end
    end
end

function Notifications:DismissCategory(category)
    for i = #self.items, 1, -1 do
        if self.items[i].category == category then self:Dismiss(self.items[i]) end
    end
end

function Notifications:Present(item)
    item.progress = UI.ProgressBar {id = "notificationProgress", position = "absolute",
        left = 12, right = 12, bottom = 5, height = 3, value = 1, max = 1,
        showLabel = false, fillColor = {59, 130, 246, 255}, borderWidth = 0,
        visible = item.timed, pointerEvents = "none"}
    local label = UI.Label {text = item.message, fontFamily = "sans", fontSize = 14,
        fontColor = C.ink, whiteSpace = "normal", lineHeight = 1.4,
        flexGrow = 1, flexShrink = 1, flexBasis = 0, minWidth = 0, pointerEvents = "none"}
    item.panel = UI.Row {width = "100%", minHeight = 64, flexShrink = 0,
        padding = 12, paddingBottom = 20, gap = 8, alignItems = "flex-start", backgroundColor = C.card,
        borderWidth = 1, borderColor = C.line, borderRadius = 9,
        -- 父卡片的 enter/leave 按整个子树触发，移到关闭按钮不会恢复计时。
        onPointerEnter = function(event) if event:IsMouse() then item.hovered = true end end,
        onPointerLeave = function(event) if event:IsMouse() then item.hovered = false end end,
        children = {
            label,
            UI.Button {id = "notificationClose", text = "×", width = 28, height = 28,
                flexShrink = 0, padding = 0, fontSize = 18, textColor = C.muted,
                backgroundColor = {0, 0, 0, 0}, borderWidth = 0, boxShadow = false,
                onClick = function() self:Dismiss(item) end},
            item.progress,
        }}
    self.stack:AddChild(item.panel)
end

function Notifications:Show(message, options)
    options = options or {}
    local duration = options.duration or 8
    local item = {message = message, category = options.category,
        duration = duration, remaining = duration, timed = duration > 0, hovered = false}
    table.insert(self.items, item)
    self:Present(item)
    return item
end

function Notifications:Update(dt, hidden, paused)
    self.layer:SetVisible(not hidden)
    for i = #self.items, 1, -1 do
        local item = self.items[i]
        if hidden then item.hovered = false end
        if not hidden and not paused and not item.hovered and item.timed then
            item.remaining = math.max(0, item.remaining - dt)
            item.progress:SetValue(item.remaining / item.duration)
            if item.remaining <= 0 then self:Dismiss(item) end
        end
    end
end

return Notifications
