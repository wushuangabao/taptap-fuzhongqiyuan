-- 声明式界面：局部干预、邻格学习、分阶段繁荣与真实历史回顾。
local UI = require("urhox-libs/UI")
local Evolution = require("OriginEvolution")
local Terrain = require("OriginTerrain")
local Widgets = require("OriginWidgets")
local S = require("OriginSimulation")
local Tips = require("OriginTips")
local Notifications = require("OriginNotifications")
local Progress = require("OriginProgress")
local Recommendation = require("OriginRecommendation")
local Settings = require("OriginSettings")
local SettingsView = require("OriginSettingsView")
local C = Widgets.Colors
local View = {}

local ACTIONS = {
    {key = "craft", title = "工艺改良", subtitle = "成功时工艺效率 +15%", icon = "craft", color = C.gold},
    {key = "foodDown", title = "更多制物", subtitle = "农业投入 −10%", icon = "foodDown", color = C.gold},
    {key = "institution", title = "制度试验", subtitle = "设立探索型制度", icon = "institution", color = C.teal},
    {key = "agriculture", title = "农艺改良", subtitle = "成功时农业效率 +12%", icon = "agriculture", color = C.green},
    {key = "foodUp", title = "更多务农", subtitle = "农业投入 +10%", icon = "foodUp", color = C.green},
    {key = "protect", title = "制度保护", subtitle = "单独使用 · 占用一轮", icon = "protect", color = C.gold},
}
local ACTION_DESCRIPTIONS = {
    agriculture = "尝试提高所选地块农业效率。失败时效率不变，仍消耗一轮；成功后更多食物可能促进人口增长。",
    craft = "尝试提高所选地块工艺效率。失败时效率不变，仍消耗一轮；成功后增加生活用品。",
    foodUp = "将劳动转向农业。温饱更有保障，但生活用品产出将减少。",
    foodDown = "将劳动转向制物。生活用品增多，但请留意户均食物是否足够。",
    institution = "将所选地块改为探索型；农业与工艺自然增长、主动改良成功率、竞争实力采用本局探索型参数。",
    protect = "单独保护所选地块的制度一整轮，降低被周边制度替代的概率。占用一轮，不改变技术和投入，不阻止迁移。每局仅3次，确认即扣除。",
}

local ACTION_REASONS = {
    unknown_action = "请选择一种行动。",
    region_out_of_bounds = "请选择地图内的地块。",
    already_won = "本局已达成现代化目标。",
    generation_limit = "已到达本局世代上限。",
    round_limit = "本局干预轮数已用完。",
    round_in_progress = "本轮仍在演进，不能追加行动。",
    no_protection_uses = "3次保护机会已经用完。",
    no_change = "所选地块已达到该行动的上限。",
    non_finite_result = "此操作会超出模型有效数值范围。",
    invalid_protection = "保护选项无效。",
    no_habitable_cells = "选区无有效地块。",
}

local function Label(text, size, color, props)
    props = props or {}
    props.text = text
    props.fontSize = size or 12
    props.fontColor = color or C.ink
    props.fontFamily = "sans"
    props.flexShrink = props.flexShrink or 1
    return UI.Label(props)
end

local function Button(text, onClick, props)
    props = props or {}
    props.text = text
    props.onClick = onClick
    props.height = props.height or 48
    props.fontSize = props.fontSize or 12
    props.borderRadius = props.borderRadius or 7
    props.backgroundColor = props.backgroundColor or {239, 241, 230, 255}
    props.hoverBackgroundColor = props.hoverBackgroundColor or {229, 235, 216, 255}
    props.pressedBackgroundColor = props.pressedBackgroundColor or {216, 228, 201, 255}
    props.textColor = props.textColor or C.green
    props.borderWidth = 1
    props.borderColor = props.borderColor or C.line
    props.boxShadow = false
    props.paddingHorizontal = props.paddingHorizontal or 12
    return UI.Button(props)
end

local function Primary(text, onClick, props)
    props = props or {}
    props.backgroundColor = C.green
    props.hoverBackgroundColor = {78, 126, 82, 255}
    props.pressedBackgroundColor = {50, 89, 58, 255}
    props.textColor = {255, 254, 241, 255}
    props.borderColor = C.green
    return Button(text, onClick, props)
end

local function Card(props)
    props.backgroundColor = props.backgroundColor or C.card
    props.borderRadius = 12
    props.borderWidth = 1
    props.borderColor = C.line
    return UI.Panel(props)
end

local function SetLabel(ctx, id, text, color)
    local label = ctx.root:FindById(id) --[[@as Label?]]
    if label then
        label:SetText(text)
        if color then label:SetFontColor(color) end
    end
end

local function SetButton(ctx, id, text, disabled)
    local button = ctx.root:FindById(id) --[[@as Button?]]
    if button then
        if text then button:SetText(text) end
        if disabled ~= nil then button:SetDisabled(disabled) end
    end
end

function View.InitTheme()
    local base = UI.Theme.GetRegisteredTheme("default-taptap") or UI.Theme.defaultTheme
    local theme = UI.Theme.ExtendTheme(base, {
        fonts = {{family = "sans", weights = {normal = "Fonts/MiSans-Regular.ttf", bold = "Fonts/MiSans-Regular.ttf"}}},
        colors = {
            primary = C.green, primaryHover = {83, 129, 87, 255}, primaryPressed = {48, 90, 59, 255},
            background = C.paper, surface = C.card, surfaceHover = {241, 243, 232, 255},
            text = C.ink, textSecondary = C.muted, border = C.line,
            disabled = {228, 231, 220, 255}, disabledText = {150, 156, 144, 255},
            success = C.green, warning = C.gold, error = C.red,
        },
        components = {Label = {fontSize = 10.5}, Button = {height = 36, fontSize = 10, borderRadius = 7, boxShadow = false}},
    })
    UI.Init({theme = theme, scale = UI.Scale.DEFAULT})
end

-- 主界面只保留地图、常驻地块数值和操作；说明交给悬停 / 长按。
local function Stat(id, name, icon, color)
    return UI.Row {flexGrow = 1, flexBasis = 0, minWidth = 0, gap = 4, alignItems = "center", children = {
        Widgets.Icon {kind = icon, color = color, width = 16, height = 18, flexShrink = 0, pointerEvents = "none"},
        Label(name, 8.5, C.muted, {whiteSpace = "nowrap", flexShrink = 0}),
        Label("—", 12, C.ink, {id = id, whiteSpace = "nowrap", maxLines = 1, flexShrink = 0}),
    }}
end

local function TimelineCard(ctx, metric, title, id, color, value)
    return UI.Column {width = "100%", gap = 5, children = {
        UI.Row {justifyContent = "space-between", children = {
            Label(title, 11, C.muted), Label(value or "—", 13, color, {id = id}),
        }},
        Widgets.Chart {ctx = ctx, metric = metric, color = color, height = 85, width = "100%", pointerEvents = "none"},
    }}
end

local function DataRow(name, id)
    return UI.Row {height = 24, gap = 6, justifyContent = "space-between", alignItems = "center", children = {
        Label(name, 9.5, C.muted), Label("—", 10.5, C.ink, {id = id}),
    }}
end

local function SelectedLandCount(ctx)
    local world, count = ctx.world, 0
    for y = ctx.regionY, ctx.regionY + world.config.regionSize - 1 do
        for x = ctx.regionX, ctx.regionX + world.config.regionSize - 1 do
            if S.IsHabitable(world.cells[(y - 1) * world.width + x]) then count = count + 1 end
        end
    end
    return count
end

local function Inspector(ctx)
    return Card {id = "inspector", flexGrow = 1, flexBasis = 0, minHeight = 0, padding = 10, gap = 4, children = {
        UI.Row {height = 22, flexShrink = 0, justifyContent = "space-between", children = {
            Label("地块详情", 12, C.ink), Label("—", 10, C.green, {id = "cellPosition"}),
        }},
        UI.ScrollView {id = "inspectorScroll", flexGrow = 1, flexBasis = 0, minHeight = 0, scrollY = true, scrollX = false,
            showScrollbar = true, scrollbarInteractive = false, children = {
                UI.Column {width = "100%", paddingRight = 18, gap = 4, children = {
                    Label("—", 11, C.green, {id = "cellRegionName", whiteSpace = "normal", maxLines = 2}),
                    Label("—", 9, C.muted, {id = "cellRegionDescription", whiteSpace = "normal", maxLines = 3}),
                    Label("—", 9, C.soil, {id = "cellTerrain", whiteSpace = "normal", maxLines = 4}),
                    UI.Row {gap = 16, children = {
                        UI.Column {flexGrow = 1, flexBasis = 0, minWidth = 0, children = {
                            DataRow("人口", "cellPopulation"), DataRow("用品/户", "cellCraft"), DataRow("农业", "cellShare"),
                        }},
                        UI.Column {flexGrow = 1, flexBasis = 0, minWidth = 0, children = {
                            DataRow("温饱", "cellFood"), DataRow("制度", "cellInstitution"), DataRow("竞争力", "cellPower"),
                        }},
                    }},
                    DataRow("制度变革概率", "cellInstitutionChange"),
                    Label("按当前状态估算每世代被邻居制度替代的概率（含已有保护）", 9, C.muted,
                        {whiteSpace = "normal", maxLines = 3}),
                    Label("—", 9, C.muted, {id = "cellTech", whiteSpace = "normal", maxLines = 2}),
                    Label("—", 10, C.green, {id = "cellNeed", whiteSpace = "normal", maxLines = 2}),
                    Label("—", 9, C.teal, {id = "cellLearning", whiteSpace = "normal", maxLines = 2}),
                    UI.Divider {color = C.line, spacing = 4},
                    Label("—", 9.5, C.muted, {id = "cellDelta", whiteSpace = "normal", maxLines = 4}),
                    Label("—", 9.5, C.muted, {id = "cellCulture", whiteSpace = "normal", maxLines = 3}),
                }},
            }},
    }}
end

function View.Choose(ctx, key)
    if ctx.phase ~= "decision" or ctx.portraitBlocked or ctx.modalOpen then return end
    ctx.action = ctx.action == key and "" or key
    View.Refresh(ctx)
end

local function ActionCard(ctx, action)
    local button = Button(nil, function() View.Choose(ctx, action.key) end,
    {id = "action_" .. action.key, height = 36, paddingHorizontal = 6,
        backgroundColor = C.card, flexGrow = 1, flexBasis = 0, minWidth = 0, flexDirection = "row", justifyContent = "center", alignItems = "center", gap = 4,
        children = {
            Widgets.Icon {width = 18, height = 22, kind = action.icon, color = action.color, pointerEvents = "none"},
            Label(action.title, 10, C.ink, {id = "actionTitle_" .. action.key, pointerEvents = "none"}),
            Label("★", 12, C.gold, {id = "recommended_" .. action.key, position = "absolute", right = 2, top = 0,
                width = 14, height = 14, visible = false, pointerEvents = "none"}),
        },
    })
    return ctx.tips:Attach(button, function()
        local valid, reason = S.ValidateAction(ctx.world, action.key, ctx.regionX, ctx.regionY)
        if action.key == "protect" then
            valid, reason = ctx.world.protectionLeft > 0, "no_protection_uses"
            if SelectedLandCount(ctx) == 0 then valid, reason = false, "no_habitable_cells" end
        end
        local cfg = ctx.world.config
        local subtitle = action.subtitle
        if action.key == "agriculture" then subtitle = string.format("成功时农业效率 +%g%%", (cfg.agricultureActionMultiplier - 1) * 100)
        elseif action.key == "craft" then subtitle = string.format("成功时工艺效率 +%g%%", (cfg.craftActionMultiplier - 1) * 100) end
        local explanation = action.title .. " · " .. subtitle .. "\n" .. ACTION_DESCRIPTIONS[action.key] .. "\n只作用于选中的一个地块。"
        if action.key == "protect" then explanation = explanation .. string.format("\n保护时制度替代概率乘 %g。", cfg.protectionMultiplier) end
        if action.key == "institution" then
            explanation = explanation .. string.format("\n探索型：农业 +%g%%、工艺 +%g%%/世代；实力倍率 %g。",
                cfg.exploreAgricultureGrowth * 100, cfg.exploreCraftGrowth * 100, cfg.explorePowerMultiplier)
        end
        if action.key == "agriculture" or action.key == "craft" or action.key == "institution" then
            local cfg = ctx.world.config
            explanation = explanation .. string.format("\n农业与工艺改良成功率：动员型 %g%%，探索型 %g%%。按确认时的制度判定。",
                cfg.mobilizeImprovementProbability * 100, cfg.exploreImprovementProbability * 100)
        end
        if ctx.phase ~= "decision" then explanation = explanation .. "\n当前不能追加干预。"
        elseif not valid then explanation = explanation .. "\n" .. (ACTION_REASONS[reason] or reason) end
        return explanation
    end)
end

local function FillActionGrid(grid, ctx, columns)
    for i = #grid.children, 1, -1 do grid.children[i]:Destroy() end
    for i = 1, #ACTIONS, columns do
        local row = UI.Row {width = "100%", gap = 6}
        for j = i, math.min(#ACTIONS, i + columns - 1) do row:AddChild(ActionCard(ctx, ACTIONS[j])) end
        grid:AddChild(row)
    end
end

local function ProgressPanel(ctx)
    return Card {padding = 14, gap = 10, backgroundColor = {232, 238, 220, 255}, children = {
        UI.Row {justifyContent = "space-between", children = {
            Label("走向全面现代化", 12, C.green), Label("0 / 5世代", 11, C.green, {id = "winStreak"}),
        }},
        UI.ProgressBar {id = "prosperityProgress", value = 0, max = 1, height = 8,
            fillColor = C.green, backgroundColor = {210, 220, 195, 255}, borderWidth = 0, showLabel = false},
        Label("80%人口温饱，且生活用品达到开局2倍；持续5世代。", 11, C.green, {whiteSpace = "normal", maxLines = 3}),
        Label("—", 11, C.ink, {id = "worldFoodShortfall"}),
        Label("—", 11, C.ink, {id = "worldCraftShortfall"}),
        Label("—", 11, C.ink, {id = "worldBothShortfall"}),
        Label("—", 10, C.teal, {id = "milestoneHistory", whiteSpace = "normal", maxLines = 3}),
    }}
end

function View.ClosePanel(ctx, skipReturn)
    local onDismiss = ctx.sheet and ctx.sheet.onDismiss
    if ctx.tips then ctx.tips:Hide() end
    if ctx.sheet then ctx.sheet.layer:Destroy(); ctx.sheet = nil end
    ctx.modalOpen, ctx.panel = false, ""
    local map = ctx.root and ctx.root:FindById("worldMap") --[[@as OriginMap?]]
    if map then map:CancelGesture() end
    if onDismiss and not skipReturn then onDismiss() end
end

-- 弹窗四周留出可点按的遮罩；没有占位的关闭按钮。
local function Modal(ctx, title, width)
    View.ClosePanel(ctx, true)
    ctx.tips:Hide()
    ctx.modalOpen = true
    local body = UI.ScrollView {id = "sheetScroll", width = "100%", flexGrow = 1, flexBasis = 0, minHeight = 0,
        scrollY = true, scrollX = false, showScrollbar = true}
    local content = UI.Column {width = "100%", padding = 16, gap = 12}
    body:AddChild(content)
    local footer = UI.Panel {id = "sheetFooter", padding = {8, 16}, gap = 8, visible = false,
        borderTopWidth = 1, borderColor = C.line}
    local panel = Card {id = "sheetCard", width = width or 460, height = 480, overflow = "hidden", children = {
        UI.Row {height = 48, flexShrink = 0, paddingHorizontal = 18, alignItems = "center", children = {
            Label(title, 15, C.ink),
        }},
        UI.Divider {color = C.line, spacing = 0}, body, footer,
    }}
    local layer = UI.Panel {id = "sheetLayer", position = "absolute", left = 0, top = 0, width = "100%", height = "100%",
        backgroundColor = {29, 47, 36, 100}, children = {
            UI.Panel {id = "modalBackdrop", position = "absolute", left = 0, top = 0, width = "100%", height = "100%",
                onClick = function() View.ClosePanel(ctx) end},
            UI.SafeAreaView {width = "100%", height = "100%", nativeMenuInset = true, pointerEvents = "box-none", children = {
                UI.Panel {flexGrow = 1, minHeight = 0, margin = 24, alignItems = "center", justifyContent = "center",
                    pointerEvents = "box-none", children = {panel}},
            }},
        }}
    ctx.root:AddChild(layer)
    local modal = {layer = layer, panel = panel, footer = footer, preferredWidth = width or 460, preferredHeight = 500}
    function modal:Close() View.ClosePanel(ctx) end
    function modal:SetFooter(widget)
        self.footer:ClearChildren()
        self.footer:AddChild(widget)
        self.footer:SetVisible(true)
    end
    function modal:Open() View.Resize(ctx); View.Refresh(ctx) end
    ctx.sheet = modal
    return modal, content
end

function View.CycleSpeed(ctx)
    if ctx.portraitBlocked or ctx.modalOpen then return end
    ctx.speed = ctx.speed == 1 and 2 or (ctx.speed == 2 and 4 or 1)
    ctx.tips:Hide()
    View.Refresh(ctx)
end

function View.OpenPanel(ctx, kind)
    if ctx.portraitBlocked then return end
    if kind == "help" then View.Help(ctx); return end
    if kind == "restart" then View.RestartDialog(ctx); return end
    if kind == "settings" then View.SettingsDialog(ctx); return end
    if kind ~= "trends" then return end
    local modal, body = Modal(ctx, "文明进程", 520)
    ctx.panel = kind
    if kind == "trends" then
        local localHistory = UI.Column {id = "localMilestoneHistory", width = "100%", gap = 6, children = {
            Label("从一片土地开始", 12, C.green),
        }}
        local history = ctx.localProgress and ctx.localProgress.history or {}
        if #history == 0 then
            localHistory:AddChild(Label("温饱的改善、探索制度的存续、技术向周边的传播，都要等真实演进来回答。", 11, C.muted,
                {whiteSpace = "normal", maxLines = 4}))
        end
        for _, event in ipairs(history) do
            localHistory:AddChild(Label(string.format("第%d轮 · %s", event.round, event.title), 11, C.green,
                {id = "localEvent_" .. event.kind, whiteSpace = "normal", maxLines = 3}))
            localHistory:AddChild(Label(event.detail, 10, C.muted, {whiteSpace = "normal", maxLines = 5}))
        end
        body:AddChild(localHistory)
        body:AddChild(ProgressPanel(ctx))
        body:AddChild(Label("实线：本局  ·  灰线：无干预基线", 10, C.muted))
        body:AddChild(TimelineCard(ctx, "population", "世界人口", "trendPopulation", C.green))
        body:AddChild(TimelineCard(ctx, "craftPerCapita", "户均生活用品", "trendCraft", C.gold))
        body:AddChild(TimelineCard(ctx, "exploreShare", "探索型人口", "trendExplore", C.teal))
        body:AddChild(Label(ctx.lastEventTitle or "文明从一小片土地开始。", 12, C.green, {whiteSpace = "normal", maxLines = 3}))
        body:AddChild(Label(ctx.lastEventDetail or "每轮一次干预，观察世界如何回应。", 11, C.muted, {whiteSpace = "normal", maxLines = 4}))
    end
    modal:Open()
end

function View.SyncZoom(ctx)
    local map = ctx.root:FindById("worldMap") --[[@as OriginMap?]]
    local slider = ctx.root:FindById("mapZoom") --[[@as Slider?]]
    if not map then return end
    ctx.syncingZoom = true
    if slider then slider:SetValue(map.camera.zoom) end
    SetLabel(ctx, "zoomLabel", string.format("%.0f%%", map.camera.zoom * 100))
    ctx.syncingZoom = false
end

local function Tool(ctx, id, icon, tip, callback, extra)
    local children = {Widgets.Icon {id = id .. "Icon", kind = icon, width = 21, height = 21, pointerEvents = "none"}}
    if extra then children[#children + 1] = Label(extra, 9, C.green, {id = "speedValue", pointerEvents = "none"}) end
    return ctx.tips:Attach(Button(nil, callback, {id = id, height = 36, flexGrow = 1, flexBasis = 0, minWidth = 0,
        paddingHorizontal = 5, flexDirection = "row", justifyContent = "center", alignItems = "center", gap = 3, children = children}), tip)
end

local function MapControls(ctx, map)
    local layerRow = UI.Row {height = 36, gap = 6}
    for _, layer in ipairs({
        {"quality", "生活品质", "生活品质：颜色越亮，生活用品越充足。"},
        {"population", "人口密度", "人口密度：颜色越深，人口越多。放大地图可查看人口数值。"},
        {"institution", "制度分布", "制度分布：青绿为探索型，沙金为动员型；金色边框表示保护。"},
        {"terrain", "地形", "地形：显示完整的山地、丘陵底色与山势；其他视图仅保留轮廓与细纹。"},
    }) do
        local key = layer[1]
        layerRow:AddChild(ctx.tips:Attach(Button(layer[2], function() ctx.layer = key; View.Refresh(ctx) end,
            {id = "layer_" .. key, height = 36, flexGrow = 1, flexBasis = 0, minWidth = 0, fontSize = 10, paddingHorizontal = 4}), layer[3]))
    end
    return UI.Column {id = "mapTools", height = 78, flexShrink = 0, gap = 6, children = {
        layerRow,
        UI.Panel {id = "mapOptions", height = 36, flexShrink = 0, flexDirection = "row", gap = 6, children = {
            UI.Row {id = "mapToggleRow", width = 362, minWidth = 310, height = 36, flexShrink = 1, alignItems = "center", gap = 4, children = {
            ctx.tips:Attach(UI.Checkbox {id = "regionToggle", checked = ctx.showRegions ~= false,
                width = 90, minWidth = 78, flexShrink = 1, height = 36, size = 16, gap = 5, children = {
                    Label("地区标注", 10, C.green, {id = "regionToggleLabel", position = "absolute", left = 22, top = 9, pointerEvents = "none"}),
                }, onChange = function(_, checked) ctx.showRegions = checked end}, "显示或隐藏地区名称与地区分界线。"),
            ctx.tips:Attach(UI.Checkbox {id = "gridToggle", checked = ctx.showGrid == true,
                width = 90, minWidth = 78, flexShrink = 1, height = 36, size = 16, gap = 5, children = {
                    Label("地块分界", 10, C.green, {id = "gridToggleLabel", position = "absolute", left = 22, top = 9, pointerEvents = "none"}),
                }, onChange = function(_, checked) ctx.showGrid = checked end}, "显示或隐藏每个地块的浅灰色细分割线。"),
            ctx.tips:Attach(UI.Checkbox {id = "migrationToggle", checked = ctx.showMigration,
                width = 90, minWidth = 78, flexShrink = 1, height = 36, size = 16, gap = 5, children = {
                    Label("迁移光点", 10, C.green, {id = "migrationToggleLabel", position = "absolute", left = 22, top = 9, pointerEvents = "none"}),
                }, onChange = function(_, checked) ctx.showMigration = checked end}, "显示居民迁往上下左右邻格的方向与流量。关闭只隐藏光点，不改变人口迁移。"),
            ctx.tips:Attach(UI.Checkbox {id = "technologyToggle", checked = ctx.showTechnology,
                width = 80, minWidth = 64, flexShrink = 1, height = 36, size = 16, gap = 5, children = {
                    Label("技术流", 10, C.green, {id = "technologyToggleLabel", position = "absolute", left = 22, top = 9, pointerEvents = "none"}),
                }, onChange = function(_, checked) ctx.showTechnology = checked end},
                "勾选显示全图技术传播；取消勾选只显示所选地块与四邻格之间的传入和传出。浅蓝为农业，深蓝为工艺；接收方本次技术增幅越大，箭头越粗。每世代学习技术差距的5%。"),
            }},
            UI.Row {id = "mapZoomRow", height = 36, flexGrow = 1, flexBasis = 0, minWidth = 148, alignItems = "center", gap = 4, children = {
            Label("100%", 10, C.muted, {id = "zoomLabel", width = 42, flexShrink = 0}),
            ctx.tips:Attach(UI.Slider {id = "mapZoom", min = 1, max = 6, value = 1, flexGrow = 1, flexBasis = 0, minWidth = 44, height = 36,
                thumbSize = 22, thumbBorderColor = C.green, thumbColor = C.card, trackHeight = 4, trackBgColor = C.line, trackFillColor = C.green,
                onChange = function(_, value) if not ctx.syncingZoom then map:SetZoom(value) end end},
                "拖动滑块、滚动鼠标滚轮或双指捏合缩放；拖动地图平移。放大后显示更多细节。"),
            ctx.tips:Attach(Button("全图", function() map:ResetCamera() end,
                {id = "resetMap", height = 36, width = 54, flexShrink = 0, fontSize = 10, paddingHorizontal = 4}), "恢复完整地图并居中。"),
            }},
        }},
    }}
end

local function Journey(ctx)
    -- 按真实字体行高撑开，避免局部成果反馈落到固定高度之外。
    return Card {id = "journey", padding = {4, 8}, gap = 2, flexShrink = 0, children = {
        ctx.tips:Attach(Label("—", 9, C.ink, {id = "shortfallSummary", whiteSpace = "nowrap"}),
            "按人口统计：缺粮指用品已达标但温饱不足；缺用品指温饱已达标；双缺指两项均不足。三类与繁荣人口合计100%。"),
        Label("—", 9, C.green, {id = "nextGoal", whiteSpace = "nowrap"}),
    }}
end

function View.Build(ctx)
    if ctx.tips then ctx.tips:Hide() end
    ctx.modalOpen, ctx.sheet, ctx.panel = false, nil, ""
    ctx.tips = Tips.New(ctx)
    local map = Widgets.Map {id = "worldMap", ctx = ctx, flexGrow = 1, flexBasis = 0, minHeight = 0, width = "100%"}
    local grid = UI.Column {id = "actionGrid", width = "100%", gap = 6}
    FillActionGrid(grid, ctx, 3)
    local root = UI.Panel {width = "100%", height = "100%", backgroundColor = C.paper, children = {
        UI.SafeAreaView {id = "safe", width = "100%", height = "100%", nativeMenuInset = true, children = {
            UI.Panel {id = "shell", flexDirection = "row", flexGrow = 1, flexBasis = 0, minHeight = 0, margin = 12, gap = 12, children = {
                UI.Column {id = "mapColumn", flexGrow = 1, flexBasis = 0, minWidth = 0, minHeight = 0, gap = 8, children = {
                    UI.Row {id = "hudStats", height = 30, flexShrink = 0, alignItems = "center", gap = 8, children = {
                        Stat("worldPopulation", "人口", "population", C.green),
                        Stat("worldCraft", "用品/户", "rose", C.gold),
                        Stat("worldProsperity", "繁荣", "institution", C.teal),
                    }},
                    MapControls(ctx, map), Journey(ctx), map,
                }},
                UI.Column {id = "detailColumn", width = 360, minHeight = 0, gap = 8, children = {
                    UI.Row {id = "functionTools", height = 78, flexShrink = 0, gap = 8, alignItems = "center", children = {
                        UI.Column {flexGrow = 1, flexBasis = 0, minWidth = 0, gap = 5, children = {
                            Label("—", 11, C.green, {id = "roundLabel"}),
                            Label("—", 10, C.muted, {id = "phaseLabel"}),
                        }},
                        UI.Column {id = "toolGrid", width = 164, gap = 6, children = {
                            UI.Row {id = "toolRow1", gap = 6, children = {
                                Tool(ctx, "openTrends", "trends", "文明进程：查看世界趋势、繁荣目标和本轮变化。", function() View.OpenPanel(ctx, "trends") end),
                                Tool(ctx, "speed", "speed", "演进速度：点击循环切换 1× → 2× → 4×。", function() View.CycleSpeed(ctx) end, "1×"),
                                Tool(ctx, "pauseToggle", "pause", function()
                                    return ctx.phase == "simulation" and (ctx.paused and "继续演进。" or "暂停演进，随时检查地图和地块。") or "暂停 / 继续：确认本轮干预后可用。"
                                end, function() if ctx.phase == "simulation" then ctx.paused = not ctx.paused; View.Refresh(ctx) end end),
                            }},
                            UI.Row {id = "toolRow2", gap = 6, children = {
                                Tool(ctx, "openHelp", "help", "玩法说明：操作方法、行动规则和胜利条件。", function() View.Help(ctx) end),
                                Tool(ctx, "openRestart", "restart", "重新开始游戏，选择沿用或更换地图种子。", function() View.RestartDialog(ctx) end),
                                Tool(ctx, "openSettings", "settings", "查看本局参数与公式。修改参数请从「重新开始」进入。", function() View.SettingsDialog(ctx) end),
                            }},
                        }},
                    }},
                    Inspector(ctx),
                    Card {id = "actionPanel", padding = 8, gap = 6, flexShrink = 0, children = {
                        UI.Row {height = 18, justifyContent = "space-between", children = {
                            Label("干预", 10, C.green, {id = "regionDescription"}),
                            Label("—", 9, C.gold, {id = "protectLeft"}),
                        }},
                        Label("—", 9, C.muted, {id = "regionLand", whiteSpace = "normal", maxLines = 2}),
                        grid,
                        Label("改良失败仍消耗一轮。", 9, C.muted,
                            {id = "improvementResult", whiteSpace = "normal", maxLines = 3}),
                        UI.Row {width = "100%", height = 36, gap = 6, children = {
                            ctx.tips:Attach(Button("跳过本轮", function() View.Skip(ctx) end,
                                {id = "skipRound", height = 36, flexGrow = 3, flexBasis = 0, minWidth = 0, fontSize = 10, paddingHorizontal = 4}),
                                function() return string.format("本轮不干预，自然演进%d世代。占用一轮，不使用制度保护。", ctx.world.config.generationsPerRound) end),
                            ctx.tips:Attach(Button("按推荐行动", function() View.FollowRecommendation(ctx) end,
                                {id = "followRecommendation", height = 36, flexGrow = 4, flexBasis = 0, minWidth = 0, fontSize = 10, paddingHorizontal = 4}), function()
                                    return ctx.recommendation and ("直接执行当前地块的星标行动。" .. (ctx.recommendationReason or "")) or "当前所选地块没有可执行的推荐行动。"
                                end),
                            ctx.tips:Attach(Primary("确认所选行动", function() View.Confirm(ctx) end,
                                {id = "confirm", height = 36, flexGrow = 5, flexBasis = 0, minWidth = 0, fontSize = 10, paddingHorizontal = 4, disabled = true}), function()
                                    return ctx.phase == "ended" and "查看本局结算。" or
                                        string.format("执行已选行动，推进%d世代。制度保护单独使用，确认时扣除次数；确认后不可撤销。", ctx.world.config.generationsPerRound)
                                end),
                        }},
                    }},
                }},
            }},
        }},
    }}
    root:AddChild(UI.SafeAreaView {id = "orientationGuard", position = "absolute", left = 0, top = 0,
        width = "100%", height = "100%", backgroundColor = C.paper, nativeMenuInset = true, visible = false, children = {
            UI.Column {flexGrow = 1, margin = 24, justifyContent = "center", alignItems = "center", gap = 18, children = {
                Widgets.Icon {kind = "restart", width = 48, height = 48, pointerEvents = "none"},
                Label("请横屏游玩", 20, C.green, {id = "rotateTitle", pointerEvents = "none"}),
                Label("旋转设备后继续，当前进度已保留", 11, C.muted,
                    {whiteSpace = "normal", maxLines = 2, textAlign = "center", pointerEvents = "none"}),
            }},
        }})
    ctx.root = root
    ctx.notifications = Notifications.New(root)
    ctx.onZoomChanged = function() View.SyncZoom(ctx) end
    UI.SetRoot(root, true)
    ctx.layoutSignature = nil
    ctx.viewportW, ctx.viewportH = 0, 0
    View.Resize(ctx)
    View.Refresh(ctx)
end

function View.Resize(ctx)
    if not ctx.root then return end
    local w, h = UI.GetViewportSize()
    local insets = UI.GetSafeAreaInsets()
    -- 与 SafeAreaView 使用同一坐标空间，同时让窗口旋转立即更新布局。
    local top = insets.top
    -- SDK 文档已提供此接口，当前引擎类型声明尚未收录；保留旧运行时兼容检查。
    local menuSdk = sdk --[[@as {GetNativeExitMenuRect: (fun(self: any): {left: number, top: number, right: number, bottom: number}?)?}?]]
    if menuSdk and menuSdk.GetNativeExitMenuRect then
        local menu = menuSdk:GetNativeExitMenuRect()
        if menu then top = math.max(top, menu.bottom * graphics.height / UI.GetScale()) end
    end
    local availableW, availableH = w - insets.left - insets.right, h - top - insets.bottom
    local signature = string.format("%.1f/%.1f/%.1f/%.1f", w, h, availableW, availableH)
    if ctx.layoutSignature ~= signature then
        ctx.layoutSignature = signature
        ctx.viewportW, ctx.viewportH = w, h
        ctx.tips:Hide()
        local portrait = h > w
        ctx.portraitBlocked = portrait
        ctx.root:FindById("safe"):SetVisible(not portrait)
        ctx.root:FindById("orientationGuard"):SetVisible(portrait)
        if portrait then View.ClosePanel(ctx, true) end
        local shell = ctx.root:FindById("shell")
        shell:SetStyle({flexDirection = "row", gap = 12})
        local left = ctx.root:FindById("mapColumn")
        local right = ctx.root:FindById("detailColumn")
        left:SetStyle({flexGrow = 1, flexBasis = 0, width = "auto"})
        local detailWidth = math.min(400, math.max(326, (availableW - 24) * 0.43))
        right:SetStyle({width = detailWidth, height = "auto", flexShrink = 0})
        local narrowMapTools = availableW - 36 - detailWidth < 470
        ctx.root:FindById("mapTools"):SetStyle({height = narrowMapTools and 118 or 78})
        ctx.root:FindById("mapOptions"):SetStyle({height = narrowMapTools and 76 or 36,
            flexDirection = narrowMapTools and "column" or "row", gap = narrowMapTools and 4 or 6})
        ctx.root:FindById("mapToggleRow"):SetStyle({width = narrowMapTools and "100%" or 362})
        ctx.root:FindById("mapZoomRow"):SetStyle({width = narrowMapTools and "100%" or "auto",
            flexGrow = narrowMapTools and 0 or 1, flexBasis = narrowMapTools and "auto" or 0})
        local compact = availableH < 380
        shell:SetStyle({margin = compact and 8 or 12})
        left:SetStyle({gap = compact and 6 or 8})
        ctx.root:FindById("functionTools"):SetStyle({height = compact and 36 or 78})
        ctx.root:FindById("toolGrid"):SetStyle({flexDirection = compact and "row" or "column", width = compact and 210 or 164})
        ctx.root:FindById("toolRow1"):SetStyle({flexGrow = compact and 3 or 0, flexBasis = compact and 0 or "auto"})
        ctx.root:FindById("toolRow2"):SetStyle({flexGrow = compact and 3 or 0, flexBasis = compact and 0 or "auto"})
        ctx.root:FindById("speedIcon"):SetVisible(not compact)
        local map = ctx.root:FindById("worldMap") --[[@as OriginMap?]]
        if map then map:CancelGesture() end
    end
    if ctx.sheet then
        local width = math.min(ctx.sheet.preferredWidth, math.max(220, availableW - 48))
        local height = math.min(ctx.sheet.preferredHeight, math.max(180, availableH - 48))
        if ctx.sheet.width ~= width or ctx.sheet.height ~= height then
            ctx.sheet.width, ctx.sheet.height = width, height
            ctx.sheet.panel:SetStyle({width = width, height = height})
        end
    end
end

function View.UpdateTips(ctx, dt)
    if ctx.tips then ctx.tips:Update(dt) end
    if ctx.notifications then ctx.notifications:Update(dt, ctx.portraitBlocked, Evolution.IsPaused(ctx)) end
end

-- 从真实行动记录生成反馈，后续制度变化或切换选区不会改写本次抽签结果。
local function ImprovementResult(world, concise)
    local record = world.actions[#world.actions]
    if not record or not record.improvements or #record.improvements == 0 then return nil end
    local successes = 0
    for _, outcome in ipairs(record.improvements) do
        if outcome.succeeded then successes = successes + 1 end
    end
    local name = record.action == "agriculture" and "农艺改良" or "工艺改良"
    local multiplier = record.action == "agriculture" and world.config.agricultureActionMultiplier or world.config.craftActionMultiplier
    if concise then
        if successes == 0 then return name .. "未成功" end
        if #record.improvements == 1 then
            return string.format("%s成功！地块效率 +%g%%", name, (multiplier - 1) * 100)
        end
        return string.format("%s：%d / %d格成功！成功地块效率 +%g%%",
            name, successes, #record.improvements, (multiplier - 1) * 100)
    end
    local result = #record.improvements == 1 and
        string.format("%s（成功率%g%%）", successes == 1 and "成功" or "未成功", record.improvements[1].probability * 100) or
        string.format("%d / %d格成功", successes, #record.improvements)
    return string.format("第%d轮 · %s%s\n%s", record.round, name, result,
        successes > 0 and string.format("成功地块效率 +%g%%。", (multiplier - 1) * 100) or "本轮已消耗，未获得改良增幅。")
end

function View.Refresh(ctx)
    if not ctx.root then return end
    local world = ctx.world
    local stats = S.Statistics(world)
    SetLabel(ctx, "worldPopulation", string.format("%.0f户", stats.population))
    SetLabel(ctx, "worldCraft", string.format("%.3f", stats.craftPerCapita))
    SetLabel(ctx, "worldProsperity", string.format("%.1f%%", stats.prosperousShare * 100))
    SetLabel(ctx, "shortfallSummary", string.format("缺粮 %.1f%% · 缺用品 %.1f%% · 双缺 %.1f%%",
        stats.foodShortfallShare * 100, stats.craftShortfallShare * 100, stats.bothShortfallShare * 100))
    SetLabel(ctx, "worldFoodShortfall", string.format("用品达标但缺粮：%.1f%%人口", stats.foodShortfallShare * 100))
    SetLabel(ctx, "worldCraftShortfall", string.format("温饱达标但缺用品：%.1f%%人口", stats.craftShortfallShare * 100))
    SetLabel(ctx, "worldBothShortfall", string.format("两项都不足：%.1f%%人口", stats.bothShortfallShare * 100))
    local latest = ctx.localProgress and ctx.localProgress.history[#ctx.localProgress.history]
    SetLabel(ctx, "nextGoal", stats.prosperousShare >= world.config.victoryShare and
        string.format("稳住繁荣 · 连续 %d / %d 世代", world.prosperousStreak, world.config.victoryStreak) or
        (latest and "局部成果 · " .. latest.title or Progress.Advice(stats)))
    local level = Progress.Level(world.maxProsperousShare)
    local stages = {}
    for i, step in ipairs(Progress.milestones) do
        if level >= i then stages[#stages + 1] = step.title end
    end
    SetLabel(ctx, "milestoneHistory", #stages > 0 and "已达阶段：" .. table.concat(stages, " → ") or "下一阶段：10%人口繁荣，点亮核心")
    SetLabel(ctx, "trendPopulation", string.format("%.0f户", stats.population))
    SetLabel(ctx, "trendCraft", string.format("%.3f", stats.craftPerCapita))
    SetLabel(ctx, "trendExplore", string.format("%.1f%%", stats.exploreShare * 100))
    local displayRound = math.min(world.config.rounds, world.round + (ctx.phase == "decision" and 1 or 0))
    SetLabel(ctx, "roundLabel", string.format("第 %d / %d 轮", displayRound, world.config.rounds))
    SetLabel(ctx, "phaseLabel", string.format("世代 %d · %s", world.generation,
        ctx.phase == "decision" and "决策" or (ctx.phase == "ended" and "结束" or (ctx.paused and "暂停" or "演进"))))
    SetButton(ctx, "pauseToggle", nil, ctx.phase ~= "simulation")
    local pauseIcon = ctx.root:FindById("pauseToggleIcon") --[[@as OriginIcon?]]
    if pauseIcon then pauseIcon.kind = ctx.paused and "play" or "pause" end
    SetLabel(ctx, "protectLeft", string.format("保护 %d / %d", world.protectionLeft, world.config.protectionUses))
    SetLabel(ctx, "winStreak", string.format("%d / %d世代", world.prosperousStreak, world.config.victoryStreak))
    local progress = ctx.root:FindById("prosperityProgress") --[[@as ProgressBar?]]
    if progress then progress:SetValue(stats.prosperousShare) end
    SetLabel(ctx, "speedValue", tostring(ctx.speed) .. "×")
    local migration = ctx.root:FindById("migrationToggle") --[[@as Checkbox?]]
    if migration then migration:SetChecked(ctx.showMigration) end
    local regions = ctx.root:FindById("regionToggle") --[[@as Checkbox?]]
    if regions then regions:SetChecked(ctx.showRegions ~= false) end
    local grid = ctx.root:FindById("gridToggle") --[[@as Checkbox?]]
    if grid then grid:SetChecked(ctx.showGrid == true) end
    local technology = ctx.root:FindById("technologyToggle") --[[@as Checkbox?]]
    if technology then technology:SetChecked(ctx.showTechnology) end
    for _, key in ipairs({"quality", "population", "institution", "terrain"}) do
        local button = ctx.root:FindById("layer_" .. key)
        if button then button:SetStyle({backgroundColor = ctx.layer == key and {221, 232, 207, 255} or C.card,
            borderColor = ctx.layer == key and {150, 176, 129, 255} or C.line}) end
    end
    local cell, metric = world.cells[ctx.selectedIndex], world.metrics[ctx.selectedIndex]
    local region = world.regions and world.regions[world.cellRegionIds[ctx.selectedIndex]]
    SetLabel(ctx, "cellRegionName", region and region.name or "本地聚落")
    SetLabel(ctx, "cellRegionDescription", region and region.description or "")
    local terrain = Terrain.Profile(cell.terrainKind, world.config)
    SetLabel(ctx, "cellPosition", string.format("(%02d, %02d)", cell.x, cell.y))
    SetLabel(ctx, "cellTerrain", string.format("%s · 软承载 %.1f户（地形 ×%.2f）\n迁移效率 %g%% · 跨格取较慢一侧",
        terrain.name, cell.landCapacity, terrain.capacityMultiplier, cell.migrationMultiplier * 100), C.soil)
    SetLabel(ctx, "cellPopulation", string.format("%.2f户", cell.population), C.ink)
    SetLabel(ctx, "cellFood", string.format("%.3f %s", metric.foodRatio, metric.foodRatio >= 1 and "温饱" or "缺粮"), metric.foodRatio >= 1 and C.green or C.red)
    SetLabel(ctx, "cellCraft", string.format("%.3f", metric.craftPerCapita), C.ink)
    SetLabel(ctx, "cellShare", string.format("%.1f%%", cell.foodShare * 100), C.ink)
    SetLabel(ctx, "cellInstitution", (cell.institution == "explore" and "探索型" or "动员型") ..
        (cell.protectionTicks > 0 and string.format(" · 保护%d", cell.protectionTicks) or ""), cell.institution == "explore" and C.teal or C.soil)
    SetLabel(ctx, "cellPower", string.format("%.2f", metric.power), C.ink)
    SetLabel(ctx, "cellInstitutionChange", string.format("%.2f%% / 世代",
        S.InstitutionChangeProbability(world, ctx.selectedIndex) * 100), C.ink)
    SetLabel(ctx, "cellTech", string.format("农业效率 %.3f    工艺效率 %.3f", cell.agriculture, cell.craft))
    SetLabel(ctx, "cellNeed", Progress.CellNeed(metric, world), C.green)
    SetLabel(ctx, "cellLearning", "每世代向上下左右邻格学习技术差距的5%")
    SetLabel(ctx, "cellDelta", "尚无世代变化")
    SetLabel(ctx, "cellCulture", "")
    SetLabel(ctx, "regionDescription", string.format("所选地块 (%d,%d)", ctx.regionX, ctx.regionY))
    local selectedLand = SelectedLandCount(ctx)
    SetLabel(ctx, "regionLand", string.format("干预范围 · %d / %d 格\n%s · 两类改良成功率 %g%%",
        selectedLand, world.config.regionSize ^ 2, cell.institution == world.config.exploreInstitution and "探索型" or "动员型",
        S.ImprovementProbability(cell, world.config) * 100))
    SetLabel(ctx, "improvementResult", ImprovementResult(world) or "改良失败仍消耗一轮。")
    if world.lastReport then
        local delta = world.lastReport.deltas[ctx.selectedIndex]
        if delta then
            SetLabel(ctx, "cellDelta", string.format("人口 %.2f户 → %.2f户  /  自然 %+.2f户  /  迁入 +%.2f户  /  迁出 −%.2f户",
                delta.before.population, delta.after.population, delta.natural, delta.incoming, delta.outgoing))
            SetLabel(ctx, "cellCulture", string.format("文化 %+.2f个百分点 · 制度 %+.2f个百分点", (delta.cultureChange or 0) * 100, (delta.institutionFoodChange or 0) * 100))
            SetLabel(ctx, "cellLearning", string.format("邻格传授：农业 +%.3f · 工艺 +%.3f", delta.agricultureLearned, delta.craftLearned))
        end
    end
    ctx.recommendation, ctx.recommendationReason = Recommendation.Choose(world, ctx.regionX, ctx.regionY)
    for _, action in ipairs(ACTIONS) do
        local valid = S.ValidateAction(world, action.key, ctx.regionX, ctx.regionY)
        local disabled = ctx.phase ~= "decision" or not valid
        SetButton(ctx, "action_" .. action.key, nil, disabled)
        local button = ctx.root:FindById("action_" .. action.key)
        local selected = ctx.action == action.key
        if button then button:SetStyle({backgroundColor = not disabled and selected and {231, 239, 217, 255} or C.card,
            borderColor = not disabled and selected and C.green or C.line}) end
        SetLabel(ctx, "actionTitle_" .. action.key, action.title, disabled and {157, 163, 151, 255} or C.ink)
        local badge = ctx.root:FindById("recommended_" .. action.key)
        if badge then badge:SetVisible(not disabled and action.key == ctx.recommendation) end
    end
    local valid = S.ValidateAction(world, ctx.action, ctx.regionX, ctx.regionY)
    SetButton(ctx, "skipRound", nil, ctx.phase ~= "decision" or not S.ValidateAction(world, "skip", ctx.regionX, ctx.regionY))
    SetButton(ctx, "followRecommendation", nil, ctx.phase ~= "decision" or not ctx.recommendation)
    SetButton(ctx, "confirm", ctx.phase == "ended" and "查看结算" or "确认所选行动",
        ctx.phase ~= "ended" and (ctx.phase ~= "decision" or not valid))
end

local function BeginRound(ctx, action)
    if ctx.phase ~= "decision" or ctx.portraitBlocked or ctx.modalOpen then return end
    local candidate = action ~= "skip" and Progress.Local.Capture(ctx.world, action, ctx.regionX, ctx.regionY) or nil
    local ok, reason = S.ApplyAction(ctx.world, action, ctx.regionX, ctx.regionY)
    if not ok then ctx.notifications:Show(ACTION_REASONS[reason] or reason); return end
    ctx.localProgress = ctx.localProgress or Progress.Local.New()
    if action == "skip" then ctx.localProgress.pending = nil
    else Progress.Local.CommitAction(ctx.localProgress, ctx.world, candidate) end
    View.ClosePanel(ctx)
    ctx.action = action
    ctx.phase = "simulation"
    ctx.paused = false
    ctx.ticksRemaining = ctx.world.config.generationsPerRound
    ctx.accumulator = 0
    Evolution.Reset(ctx)
    Evolution.Prepare(ctx)
    ctx.roundStart = ctx.world.generation
    ctx.roundRegion = {x = ctx.regionX, y = ctx.regionY}
    ctx.lastEventTitle = action == "skip" and "本轮不干预，观察文明自然演进。" or "干预已经确认，文明正在回应。"
    ctx.lastEventDetail = action == "skip" and "未改变地块，也未使用制度保护。" or ACTION_DESCRIPTIONS[action]
    local improvementResult = ImprovementResult(ctx.world)
    if improvementResult then
        ctx.lastEventTitle = "改良尝试已结束，文明继续演进。"
        ctx.lastEventDetail = improvementResult
        ctx.notifications:Show(ImprovementResult(ctx.world, true))
    end
    print(string.format("[行动] 第%d轮 %s 区域(%d,%d) 世代%d", ctx.world.round, ctx.action, ctx.regionX, ctx.regionY, ctx.world.generation))
    View.Refresh(ctx)
end

function View.Confirm(ctx)
    if ctx.portraitBlocked or ctx.modalOpen then return end
    if ctx.phase == "ended" then View.Ending(ctx); return end
    BeginRound(ctx, ctx.action)
end

function View.Skip(ctx)
    BeginRound(ctx, "skip")
end

function View.FollowRecommendation(ctx)
    if ctx.phase ~= "decision" or ctx.portraitBlocked or ctx.modalOpen then return end
    local action = Recommendation.Choose(ctx.world, ctx.regionX, ctx.regionY)
    if action then BeginRound(ctx, action) end
end

function View.OnGeneration(ctx)
    if ctx.localProgress then
        for _, event in ipairs(Progress.Local.Evaluate(ctx.localProgress, ctx.world)) do
            print(string.format("[局部成果] %s 第%d轮 世代%d", event.kind, event.round, event.generation))
        end
    end
    local report = ctx.world.lastReport
    if not ctx.tipsClosed and report then
        if not ctx.seenMigration and (report.totalMigration or 0) > 0 then
            ctx.seenMigration = true
            ctx.notifications:Show("居民向生活更好的相邻地块迁移，会将原本的习惯带到当地。", {category = "tutorial"})
        end
        if not ctx.seenCompetition and #(report.changes or {}) > 0 then
            ctx.seenCompetition = true
            ctx.notifications:Show("竞争力强的地块，其制度会向周边传播。", {category = "tutorial"})
        end
    end
    local level = Progress.Level(ctx.world.maxProsperousShare)
    local previous = ctx.milestoneLevel or 0
    if level > previous then
        ctx.milestoneLevel = level
        local step = Progress.milestones[level]
        ctx.notifications:Show(string.format("里程碑：已有%.0f%%人口达到繁荣", step.share * 100))
        print(string.format("[阶段] %s 世代%d", step.title, ctx.world.generation))
    end
end

function View.RoundReport(ctx)
    local world = ctx.world
    local history = world.history
    local previous = history[math.max(1, ctx.roundStart + 1)]
    previous = previous.summary or previous
    local current = S.Statistics(world)
    ctx.lastEventTitle = string.format("这%d世代：人口 %+.0f户，生活用品 %+.1f%%。", world.generation - ctx.roundStart, current.population - previous.population,
        100 * (current.craftPerCapita / previous.craftPerCapita - 1))
    local migrated, replaced = 0, 0
    for i = ctx.roundStart + 2, #history do
        local report = history[i]
        for _, flow in ipairs(report.flows or {}) do migrated = migrated + flow.amount end
        replaced = replaced + #(report.changes or {})
    end
    ctx.lastEventDetail = string.format("迁移流量合计 %.1f户 · 制度替代 %d次 · 探索型人口 %.1f%%", migrated, replaced, current.exploreShare * 100)
    if not ctx.tipsClosed and not ctx.seenProsperity and current.prosperousPopulation > 0 then
        ctx.seenProsperity = true
        ctx.notifications:Show("繁荣出现了！满足温饱的同时，生活用品也达到人均富足。", {category = "tutorial"})
    end
    ctx.action = ""
    View.Refresh(ctx)
end

function View.Help(ctx)
    if ctx.modalOpen or ctx.portraitBlocked then return end
    local modal, body = Modal(ctx, "一部没有预设结局的文明史", 660)
    local poem = {"是给文明以岁月，", "还是给岁月以文明？", "我们免于此虑，", "只因活在例外的时代。", "这个时代，", "靠什么开启，会不会结束？"}
    local lines = {}
    for _, text in ipairs(poem) do lines[#lines + 1] = Label(text, 12, C.green, {textAlign = "center"}) end
    body:AddChild(UI.Column {width = "100%", gap = 3, children = lines})
    body:AddChild(UI.Divider {color = C.line, spacing = 6})
    for _, text in ipairs({
        "1. 每轮只能选择一个地块进行干预。点地图选中地块，再选择行动并确认；每轮只能执行一种行动，只作用于这一格。",
        "跳过本轮：不执行干预或制度保护，让世界自然演进一轮。",
        "按推荐行动：直接执行当前地块的金色星标行动。建议按成功率估算本地温饱与用品改善，不保证最优。",
        string.format("农业与工艺改良：动员型成功率%g%%，探索型%g%%。成功时分别提高效率%g%%、%g%%；失败无改良增幅，仍推进一轮。制度保护为独立行动，不能与改良同时使用。",
            ctx.world.config.mobilizeImprovementProbability * 100, ctx.world.config.exploreImprovementProbability * 100,
            (ctx.world.config.agricultureActionMultiplier - 1) * 100, (ctx.world.config.craftActionMultiplier - 1) * 100),
        "滑块、鼠标滚轮或双指捏合缩放；单指拖动地图，「全图」复位。",
        "地图按种子生成四片连通地区。名称与细边界帮助定位；详情中的开局特点不代表永久加成。实际通行由地形决定。",
        "左侧农业长方块固定宽度，由下向上最多六块，表示平均粮食产出提高；缺粮偏橙红，温饱临界偏黄，稍有盈余快速转绿。颜色连续渐变，在温饱线附近变化最明显。右下玫瑰越多，表示平均手工业产出越高；右侧住宅越密，表示人口越多。三者随每次结算更新。",
        "人口以户为单位。平原承载高、通行快，丘陵居中，山地承载低、通行慢。软承载影响拥挤程度，不是户数硬上限；粮食还取决于农艺与劳动分配。迁移效率影响每世代迁移户数，途中不另设等待队列。",
        "悬停或长按按钮查看说明；点击弹窗外返回地图。",
        string.format("2. 每轮一次干预，推进%d世代；制度保护需单独使用，占用一轮，每局3次。", ctx.world.config.generationsPerRound),
        "3. 演进中可暂停检查、切换图层；不额外获得行动。",
        "4. 食物支持人口，生活用品提高福利；迁移与制度都按上下左右邻格结算。",
        string.format("5. 繁荣人口达到80%%并持续5世代即获胜，最多%d轮。", ctx.world.config.rounds),
        "6. 农业与工艺每世代向上下左右邻格学习差距的5%，先培育核心，再补足缺粮或缺用品的地区。",
        "10%点亮核心、30%繁荣扩散、60%灯火成网；历史里程碑会保留，胜利仍需连续达标。",
    }) do body:AddChild(Label(text, 12, C.ink, {whiteSpace = "normal", maxLines = 4})) end
    body:AddChild(UI.Checkbox {label = "关闭新手提示", checked = ctx.tipsClosed,
        onChange = function(_, checked)
            ctx.tipsClosed = checked
            if checked then ctx.notifications:DismissCategory("tutorial") end
        end})
    body:AddChild(Label("受吴乐旻《富种起源》及相关理论研究启发的策略模拟。规则经过游戏化简化。", 10, C.muted,
        {whiteSpace = "normal", maxLines = 2}))
    modal:Open()
end

function View.SettingsDialog(ctx)
    if ctx.modalOpen or ctx.portraitBlocked then return end
    SettingsView.Open(ctx, Settings.New(ctx.world.config, false), Modal)
end

function View.RestartDialog(ctx, draft)
    if (ctx.modalOpen and not draft) or ctx.portraitBlocked then return end
    draft = draft or {config = Settings.Copy(ctx.world.config), seedText = tostring(ctx.world.seed)}
    local modal, body = Modal(ctx, "重新开始", 460)
    modal.preferredHeight = 460
    body:AddChild(Card {width = "100%", padding = 12, gap = 4, backgroundColor = C.paper, children = {
        Label("当前地图随机种子", 10, C.muted),
        Label(tostring(ctx.world.seed), 20, C.green, {id = "currentMapSeed"}),
    }})
    body:AddChild(Label("输入随机种子", 11, C.green))
    local hint = Label("请输入0～2147483647之间的整数。", 9, C.muted, {id = "seedInputHint", whiteSpace = "normal", maxLines = 2})
    local function ParseSeed(value)
        local digits = value:match("^%s*(%d+)%s*$")
        local seed = digits and math.tointeger(tonumber(digits))
        if seed and seed >= 0 and seed <= 2147483647 then return seed end
    end
    local function SubmitSeed(value)
        local seed = ParseSeed(value)
        if not seed then
            hint:SetText("种子无效：请输入0～2147483647之间的整数。")
            hint:SetFontColor(C.red)
            return
        end
        modal:Close()
        ctx.restart(seed, draft.config)
    end
    local field = UI.TextField {id = "restartSeedInput", value = draft.seedText,
        height = 40, flexGrow = 1, flexBasis = 0, minWidth = 0, fontSize = 12,
        placeholder = "输入地图种子", textColor = C.ink, backgroundColor = C.card,
        borderColor = C.line, focusedBorderColor = C.green,
        onChange = function(_, value)
            draft.seedText = value
            hint:SetText("请输入0～2147483647之间的整数。")
            hint:SetFontColor(C.muted)
        end,
        onSubmit = function(_, value) SubmitSeed(value) end,
    }
    body:AddChild(hint)
    body:AddChild(UI.Row {width = "100%", gap = 8, alignItems = "center", children = {
        field,
        Primary("使用此种子重开", function() SubmitSeed(field:GetValue()) end, {id = "restartWithSeed", height = 40, width = 120}),
    }})
    body:AddChild(Button("设置下一局参数", function()
        draft.seedText = field:GetValue()
        SettingsView.Open(ctx, Settings.New(draft.config, true), Modal,
            function(config) draft.config = config; draft.changed = true; View.RestartDialog(ctx, draft) end,
            function() View.RestartDialog(ctx, draft) end)
    end, {id = "restartSettings", height = 40}))
    body:AddChild(Label(draft.changed and "已保存参数草稿，下方任一重开方式都会应用；关闭此窗口则放弃。" or
        "新一局沿用当前参数；可在设置中修改，或恢复默认。", 10, C.muted, {id = "restartSettingsHint", whiteSpace = "normal"}))
    modal:SetFooter(UI.Row {justifyContent = "flex-end", gap = 9, flexWrap = "wrap", children = {
        Button("同种子重开", function() modal:Close(); ctx.restart(nil, draft.config) end, {id = "restartSameSeed", width = 116}),
        Primary("重新随机种子", function()
            -- UI使用独立的Lua随机源，不消耗当前世界的模拟随机序列。
            local seed = math.random(1, 2147483646)
            if seed == ctx.world.seed then seed = seed % 2147483646 + 1 end
            modal:Close()
            ctx.restart(seed, draft.config)
        end, {id = "restartRandomSeed", width = 128}),
    }})
    modal:Open()
end

function View.Ending(ctx)
    if ctx.modalOpen then return end
    local world = ctx.world
    local stats = S.Statistics(world)
    local modal, body = Modal(ctx, world.won and "灯火相连 · 现代化达成" or "文明仍在路上", 760)
    body:AddChild(Label(world.won and string.format("第%d轮 · 第%d世代：80%%居民持续5世代生活在繁荣地区。", world.round, world.generation) or
        string.format("%d个世代已经结束。未达通关门槛，不代表没有进步。", world.generation), 13, C.green,
        {whiteSpace = "normal", maxLines = 2}))
    body:AddChild(Label(string.format("最高繁荣 %.1f%%   /   当前户均生活用品 %.3f   /   探索型人口 %.1f%%",
        world.maxProsperousShare * 100, stats.craftPerCapita, stats.exploreShare * 100), 10, C.ink,
        {whiteSpace = "normal", maxLines = 2}))
    body:AddChild(UI.Column {width = "100%", gap = 18, children = {
        TimelineCard(ctx, "prosperousShare", "繁荣人口占比", "endingProsperity", C.green, string.format("%.1f%%", stats.prosperousShare * 100)),
        TimelineCard(ctx, "craftPerCapita", "户均生活用品", "endingCraft", C.gold, string.format("%.3f", stats.craftPerCapita)),
        TimelineCard(ctx, "exploreShare", "探索型人口占比", "endingExplore", C.teal, string.format("%.1f%%", stats.exploreShare * 100)),
    }})
    local firstMigration, firstChange, bestPoint
    for i, item in ipairs(world.history) do
        local point = item.summary or item
        if not firstMigration and #(item.flows or {}) > 0 then firstMigration = i - 1 end
        if not firstChange and #(item.changes or {}) > 0 then firstChange = i - 1 end
        if not bestPoint or point.prosperousShare > bestPoint.share then
            bestPoint = {generation = i - 1, share = point.prosperousShare}
        end
    end
    body:AddChild(Label("从真实记录回望", 11, C.green))
    if firstMigration then body:AddChild(Label(string.format("世代 %d：首次人口迁移。个体追求更好生活，反过来改变地区条件。", firstMigration), 9.5, C.ink,
        {whiteSpace = "normal", maxLines = 4})) end
    if firstChange then body:AddChild(Label(string.format("世代 %d：首次制度替代。传播由竞争力决定，而不是制度的名字。", firstChange), 9.5, C.ink,
        {whiteSpace = "normal", maxLines = 4})) end
    if bestPoint then body:AddChild(Label(string.format("世代 %d：繁荣人口占比达到本局最高 %.1f%%。", bestPoint.generation, bestPoint.share * 100), 9.5, C.ink)) end
    local base = ctx.baseline[world.generation + 1]
    base = base.summary or base
    body:AddChild(Label(string.format("同种子同世代无干预对照：用品 %.3f，繁荣 %.1f%%。", base.craftPerCapita, base.prosperousShare * 100), 9, C.muted,
        {whiteSpace = "normal", maxLines = 2}))
    body:AddChild(Label("技术沿上下左右邻格传播。农业与工艺共同维持繁荣。", 8.5, C.muted,
        {whiteSpace = "normal", maxLines = 2}))
    modal:SetFooter(UI.Row {justifyContent = "flex-end", gap = 9, children = {
        Primary("同种子再试一次", function() modal:Close(); ctx.restart() end, {width = 144}),
    }})
    modal:Open()
end
return View
