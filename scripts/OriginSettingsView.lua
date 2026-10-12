-- 查看与编辑共用此窗口。编辑只写 Settings 草稿，确认重开才进入模拟。
local UI = require("urhox-libs/UI")
local Widgets = require("OriginWidgets")
local Settings = require("OriginSettings")
local S = require("OriginSimulation")
local C = Widgets.Colors
local V = {}

local function Label(text, props)
    props = props or {}
    props.text, props.fontFamily = text, "sans"
    props.fontSize, props.fontColor = props.fontSize or 11, props.fontColor or C.ink
    props.whiteSpace, props.flexShrink = "normal", 1
    return UI.Label(props)
end

local function Button(text, click, id, primary)
    return UI.Button {id = id, text = text, onClick = click, height = 36, fontSize = 11,
        paddingHorizontal = 12, borderRadius = 7, borderWidth = 1, borderColor = C.line,
        textColor = primary and C.card or C.green, backgroundColor = primary and C.green or C.paper,
        boxShadow = false}
end

function V.Open(ctx, session, makeModal, onSave, onCancel, page)
    page = page or "main"
    local editable = session.editable
    local title = page == "migration" and "移民吸引 · 公式与参数" or
        page == "competition" and "制度竞择 · 公式与参数" or "游戏参数"
    local modal, body = makeModal(ctx, title .. (editable and " · 重开草稿" or " · 本局只读"), 740)
    modal.preferredHeight = 660
    ctx.panel = "settings_" .. page
    local function Open(target) V.Open(ctx, session, makeModal, onSave, onCancel, target) end
    modal.onDismiss = page ~= "main" and function() Open("main") end or onCancel
    local errorLabel = Label("", {id = "settingsError", fontColor = C.red, fontSize = 10, width = "100%"})
    local saveButton
    local curveSummary

    local function Feedback()
        errorLabel:SetText(Settings.Error(session) or (editable and "保存仅更新重开草稿，确认重开后生效。" or "本局参数已锁定；通过「重新开始 → 设置」修改下一局。"))
        errorLabel:SetFontColor(Settings.Error(session) and C.red or C.muted)
        if saveButton then saveButton:SetDisabled(Settings.Error(session) ~= nil) end
        if curveSummary then
            local cfg = session.config
            curveSummary:SetText(string.format("温饱比 0.5 / 1 / 1.5 时：%+.1f%% / 0%% / %+.1f%%\n虚线为 ±%.1f%% 上限；不含迁移。",
                S.PopulationChangeRate(0.5, cfg) * 100, S.PopulationChangeRate(1.5, cfg) * 100, cfg.naturalGrowthRate * 100))
        end
    end

    local function TipLabel(text, tip, id)
        local label = Label(text, {id = id, width = "100%", fontSize = 11, fontColor = C.green, pointerEvents = "auto"})
        return ctx.tips:Attach(label, tip, true)
    end

    local function Field(key, slider)
        local f = assert(Settings.byKey[key])
        local input, control
        local syncing = false
        local function Change(text)
            local valid = Settings.Set(session, key, text)
            input:SetStyle({borderColor = valid and C.line or C.red})
            if valid and control then
                syncing = true
                control:SetValue((session.config[key] - f.offset) * f.scale)
                syncing = false
            end
            Feedback()
        end
        input = UI.TextField {id = "setting_" .. key, value = session.texts[key] or Settings.Display(session.config, key),
            disabled = not editable, height = 34, width = 94, fontSize = 12, maxLength = 20,
            textColor = C.ink, backgroundColor = C.card, borderColor = session.errors[key] and C.red or C.line,
            focusedBorderColor = C.green, onChange = function(_, text) Change(text) end}
        local column = UI.Column {flexGrow = 1, flexBasis = 0, minWidth = 0, gap = 5, children = {
            TipLabel(f.name .. (f.unit ~= "" and "（" .. f.unit .. "）" or ""), f.tip, "settingLabel_" .. key),
            UI.Row {alignItems = "center", gap = 7, children = {
                input, Label(editable and string.format("范围 %g～%g%s", f.min, f.max, f.unit) or f.unit,
                    {width = 130, height = 32, fontSize = 9, fontColor = C.muted}),
            }},
        }}
        if slider then
            control = UI.Slider {id = "settingSlider_" .. key, min = f.min, max = f.max,
                step = 0.1, value = (session.config[key] - f.offset) * f.scale, disabled = not editable,
                width = "100%", height = 22,
                onChange = function(_, value)
                    if not editable or syncing then return end
                    local text = string.format("%.1f", value)
                    input:SetValue(text)
                    Change(text)
                end}
            column:AddChild(control)
        end
        return column
    end

    local function Section(titleText, tip, keys)
        local card = UI.Column {width = "100%", gap = 9, padding = 12, backgroundColor = C.paper, borderRadius = 8}
        card:AddChild(TipLabel(titleText, tip))
        for i = 1, #keys, 2 do
            local row = UI.Row {width = "100%", gap = 18, children = {Field(keys[i])}}
            if keys[i + 1] then row:AddChild(Field(keys[i + 1])) end
            card:AddChild(row)
        end
        body:AddChild(card)
    end

    body:AddChild(Label(editable and "悬停或长按参数名查看解释。自然增长和迁移按每世代计算；改良成功率与增幅按每次行动计算。" or
        "这里展示本局实际使用的参数。悬停或长按参数名查看解释；公式详情也可查看。", {fontColor = C.muted, fontSize = 10}))
    if page == "main" then
        Section("农业自然增长率", "每世代先按制度自然增长，再向四邻格学习。两种制度可以分别设置。",
            {"mobilizeAgricultureGrowth", "exploreAgricultureGrowth"})
        Section("工艺自然增长率", "工艺效率自动积累，不等于人均用品必然增长；人口和农业劳动占比也会改变结果。",
            {"mobilizeCraftGrowth", "exploreCraftGrowth"})
        Section("技术改良成功率", "两种主动改良共用这一组制度成功率。",
            {"mobilizeImprovementProbability", "exploreImprovementProbability"})
        Section("改良成功后增幅", "分别设置农业和工艺成功后的效率增幅；失败时不变。",
            {"agricultureActionMultiplier", "craftActionMultiplier"})
        Section("传播与文化", "技术学习和移民文化混合是不同的机制。",
            {"technologyDiffusion", "culturalMixRate"})
        local slopeField, capField = Field("naturalGrowthSlope", true), Field("naturalGrowthRate", true)
        slopeField:SetStyle({flexGrow = 0, flexBasis = "auto", width = "100%"})
        capField:SetStyle({flexGrow = 0, flexBasis = "auto", width = "100%"})
        local controls = UI.Column {flexGrow = 1, flexBasis = 0, minWidth = 0, gap = 12, children = {slopeField, capField}}
        curveSummary = Label("", {id = "populationCurveSummary", fontSize = 9, fontColor = C.muted})
        body:AddChild(UI.Column {width = "100%", padding = 12, gap = 8, backgroundColor = C.paper, borderRadius = 8, children = {
            TipLabel("人口随粮食变化", "粮食充足时增长，短缺时减少。曲线与实际模拟调用同一个公式；无效输入不会更新曲线。"),
            Label("ΔN / N = r × tanh[k × (s − 1)]", {fontSize = 12}),
            UI.Row {width = "100%", gap = 18, alignItems = "center", children = {
                controls,
                UI.Column {flexGrow = 1, flexBasis = 0, minWidth = 0, gap = 6, children = {
                    Widgets.PopulationCurve {id = "populationCurve", config = session.config, width = "100%", height = 175, pointerEvents = "none"},
                    curveSummary,
                }},
            }},
        }})
        local migration = Button("移民吸引相关  →", function() Open("migration") end, "settingsMigration")
        local competition = Button("制度竞择相关  →", function() Open("competition") end, "settingsCompetition")
        body:AddChild(ctx.tips:Attach(migration, "查看迁移效用、迁出量和文化混合公式；设置缺粮惩罚、迁移阻力、迁出上限与地形通行效率。", true))
        body:AddChild(ctx.tips:Attach(competition, "查看制度实力、替代概率和习惯变化公式；设置实力倍率、替代强度与保护效果。", true))
    else
        local formulas = page == "migration" and Settings.migrationFormula or Settings.competitionFormula
        local formulaCard = UI.Column {width = "100%", gap = 8, padding = 12, backgroundColor = C.paper, borderRadius = 8}
        for _, formula in ipairs(formulas) do formulaCard:AddChild(Label(formula, {fontSize = 11})) end
        body:AddChild(formulaCard)
        if page == "migration" then
            Section("迁移吸引与流量", "效用差驱动迁移，阻力设置门槛；人口守恒，地形减慢流量。",
                {"starvationPenalty", "migrationResistance", "migrationRate", "culturalMixRate", "terrainPlainMigration", "terrainHillMigration", "terrainMountainMigration"})
        else
            Section("实力与制度替代", "可分别改变两种制度的实力倍率；并不保证任何一方持续获胜。",
                {"craftPowerWeight", "replacementRate", "mobilizePowerMultiplier", "explorePowerMultiplier", "protectionMultiplier", "replacementCultureRate"})
        end
    end
    local buttons = UI.Row {justifyContent = "flex-end", gap = 8, flexWrap = "wrap"}
    if page ~= "main" then
        buttons:AddChild(Button("返回", function() Open("main") end, "settingsBack"))
    elseif editable then
        buttons:AddChild(Button("恢复默认", function() Settings.Reset(session); Open("main") end, "settingsReset"))
        buttons:AddChild(Button("取消", function() modal:Close() end, "settingsCancel"))
        saveButton = Button("保存并返回", function()
            local config, err = Settings.Validate(session)
            if not config then errorLabel:SetText(err); errorLabel:SetFontColor(C.red); return end
            modal.onDismiss = nil
            modal:Close()
            onSave(config)
        end, "settingsSave", true)
        buttons:AddChild(saveButton)
    else
        buttons:AddChild(Button("返回游戏", function() modal:Close() end, "settingsClose"))
    end
    modal:SetFooter(UI.Column {width = "100%", gap = 7, children = {errorLabel, buttons}})
    Feedback()
    modal:Open()
end

return V
