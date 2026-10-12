-- 执行正式 main/View 回调；控件替身仅验证行为，不作为引擎布局/视觉验收。
local T = {}
function T.Run()
    local methods = {}
    function methods:AddChild(child) child.parent = self; self.children[#self.children + 1] = child end
    function methods:FindById(id)
        if self.destroyed then return end
        if self.props.id == id then return self end
        for _, child in ipairs(self.children) do local found = child:FindById(id); if found then return found end end
    end
    function methods:Destroy()
        self.destroyed = true
        if self.parent then
            for i, child in ipairs(self.parent.children) do if child == self then table.remove(self.parent.children, i); break end end
        end
    end
    function methods:SetStyle(props) for k, v in pairs(props) do self.props[k] = v end end
    function methods:SetText(v) self.props.text = v end
    function methods:GetText() return self.props.text end
    function methods:SetDisabled(v) self.props.disabled = v end
    function methods:SetVisible(v) self.props.visible = v end
    function methods:SetChecked(v) self.props.checked = v end
    function methods:SetFontColor(v) self.props.fontColor = v end
    function methods:ClearChildren() self.children = {} end
    function methods:CancelGesture() end
    function methods:SetValue(v)
        local old = self.props.value
        self.props.value = v
        if old ~= v and self.props.onChange then self.props.onChange(self, v) end
    end
    function methods:GetValue() return self.props.value end
    function methods:GetAbsoluteLayout() return {x = 0, y = 0, w = 400, h = 200} end
    function methods:GetAbsoluteLayoutForHitTest() self.usedScrollPosition = true; return {x = 0, y = 0, w = 400, h = 200} end
    for _, event in ipairs({"Enter", "Leave", "Down", "Move", "Up", "Cancel"}) do methods["OnPointer" .. event] = function() end end
    function methods:OnClick() if self.props.onClick then self.props.onClick(self) end end
    local function Widget(props)
        local node = setmetatable({props = props or {}, children = {}}, {__index = methods})
        for _, child in ipairs((props or {}).children or {}) do node:AddChild(child) end
        return node
    end
    local ui = {Scale = {DEFAULT = 1}, Theme = {defaultTheme = {colors = {}}}, Toast = {Show = function() end}}
    for _, kind in ipairs({"Panel", "Label", "Button", "Row", "Column", "ScrollView", "SafeAreaView", "Divider", "ProgressBar", "Checkbox", "Slider", "TextField"}) do ui[kind] = Widget end
    function ui.Theme.GetRegisteredTheme() return ui.Theme.defaultTheme end
    function ui.Theme.ExtendTheme(_, theme) return theme end
    function ui.Init() end
    function ui.Layout() end
    function ui.IsLayoutDirty() return false end -- 替身的固定布局始终已计算。
    function ui.SetRoot(root) ui.root = root end
    function ui.GetScale() return 1 end
    function ui.GetViewportSize() return 1280, 720 end
    function ui.GetSafeAreaInsets() return {left = 0, right = 0, top = 0, bottom = 0} end
    local widgets = {Colors = {}}
    for _, key in ipairs({"ink", "muted", "paper", "card", "line", "green", "gold", "teal", "red", "soil"}) do widgets.Colors[key] = {0, 0, 0, 255} end
    widgets.Icon, widgets.Chart, widgets.PopulationCurve = Widget, Widget, Widget
    function widgets.Map(props) local map = Widget(props); map.camera = {zoom = 1}; return map end
    package.loaded["urhox-libs/UI"], package.loaded.OriginWidgets = ui, widgets
    graphics, input, MM_ABSOLUTE = {height = 720}, {}, 0
    SubscribeToEvent = function() end
    local S = require("OriginSimulation")
    local View = require("OriginView")
    require("main")
    Start()
    local ctx = OriginDebug.GetGame()
    local function Find(id) return assert(ctx.root:FindById(id), "缺少控件 " .. id) end
    local function Click(id) local w = Find(id); assert(not w.props.disabled, id .. " disabled"); w:OnClick() end
    local function Set(key, value) Find("setting_" .. key):SetValue(value) end
    local function Edit() Click("openRestart"); Click("restartSettings") end
    local function SameWorld(world, rng) assert(ctx.world == world and world.rng.state == rng) end
    local report = {passed = 0, failed = 0, results = {}, ok = false}
    local function Test(name, fn)
        local ok, err = pcall(fn)
        report.results[#report.results + 1] = {name = name, passed = ok, error = not ok and tostring(err) or nil}
        report[ok and "passed" or "failed"] = report[ok and "passed" or "failed"] + 1
        View.ClosePanel(ctx, true)
    end
    Test("右上角设置只读，公式子页只读，无保存或重置入口", function()
        local world, rng = ctx.world, ctx.world.rng.state
        Click("openSettings")
        assert(Find("setting_naturalGrowthRate").props.disabled and not ctx.root:FindById("settingsSave"))
        assert(not ctx.root:FindById("settingsReset"))
        Set("naturalGrowthRate", "20")
        Click("settingsMigration")
        assert(Find("setting_migrationRate").props.disabled)
        View.ClosePanel(ctx) -- Escape/遮罩也返回上一级
        assert(ctx.panel == "settings_main")
        Click("settingsCompetition")
        assert(Find("setting_replacementRate").props.disabled)
        Click("settingsBack"); Click("settingsClose")
        SameWorld(world, rng)
        assert(world.config.naturalGrowthRate == .5 and not ctx.modalOpen)
    end)
    Test("弹窗中参数名悬浮提示可用，游戏继续保持暂停", function()
        Click("openSettings")
        local label = Find("settingLabel_naturalGrowthSlope")
        assert(label.props.pointerEvents == "auto", "Label默认不参与命中，参数名必须显式开启")
        assert(label.props.width == "100%", "参数名必须有明确的悬浮命中宽度")
        label:OnPointerEnter({x = 100, y = 100, IsMouse = function() return true end})
        ctx.tips:Update(.5)
        assert(ctx.tips.popup and ctx.modalOpen and label.usedScrollPosition)
        assert(Find("buttonTip").children[1]:GetText():find("温饱线"))
        local generation = ctx.world.generation
        ctx.phase = "simulation"
        HandleUpdate("Update", {GetFloat = function() return 1 end} --[[@as UpdateEventData]])
        assert(ctx.world.generation == generation)
        ctx.phase = "decision"
    end)
    Test("重开种子输入跨设置保留，取消设置与重开均不影响当前局", function()
        local world, rng = ctx.world, ctx.world.rng.state
        Click("openRestart"); Find("restartSeedInput"):SetValue("123")
        Click("restartSettings"); Set("naturalGrowthRate", "20")
        Click("settingsCancel")
        assert(Find("restartSeedInput"):GetValue() == "123")
        Click("restartSettings")
        assert(Find("setting_naturalGrowthRate"):GetValue() == "50")
        Set("naturalGrowthRate", "25"); Click("settingsSave")
        SameWorld(world, rng)
        View.ClosePanel(ctx)
        Edit()
        assert(Find("setting_naturalGrowthRate"):GetValue() == "50")
        SameWorld(world, rng)
    end)
    Test("人口输入和滑块实时更新同一曲线；无效输入不更新且阻止保存", function()
        Edit()
        local curve = Find("populationCurve").props.config
        local before = Find("populationCurveSummary"):GetText()
        Set("naturalGrowthSlope", "3.25")
        assert(curve.naturalGrowthSlope == 3.25)
        assert(Find("settingSlider_naturalGrowthSlope"):GetValue() == 3.25)
        assert(Find("populationCurveSummary"):GetText() ~= before)
        Find("settingSlider_naturalGrowthRate"):SetValue(30)
        assert(curve.naturalGrowthRate == .3 and tonumber(Find("setting_naturalGrowthRate"):GetValue()) == 30)
        Set("naturalGrowthSlope", "")
        assert(curve.naturalGrowthSlope == 3.25 and Find("settingsSave").props.disabled)
        Click("settingsMigration"); Click("settingsBack")
        assert(Find("setting_naturalGrowthSlope"):GetValue() == "" and Find("settingsSave").props.disabled)
        Set("naturalGrowthSlope", "0")
        assert(not Find("settingsSave").props.disabled and curve.naturalGrowthSlope == 0)
    end)
    Test("主界面与公式子页共享草稿，重置包含子页参数", function()
        Edit(); Set("culturalMixRate", "75")
        Click("settingsMigration")
        assert(Find("setting_culturalMixRate"):GetValue() == "75")
        Set("culturalMixRate", "65"); Set("migrationRate", "40")
        Click("settingsBack")
        assert(Find("setting_culturalMixRate"):GetValue() == "65")
        Click("settingsCompetition"); Set("replacementRate", "0"); Click("settingsBack")
        Click("settingsReset")
        assert(Find("setting_culturalMixRate"):GetValue() == "50")
        Click("settingsMigration"); assert(Find("setting_migrationRate"):GetValue() == "24")
        Click("settingsBack"); Click("settingsCompetition"); assert(Find("setting_replacementRate"):GetValue() == "20")
    end)
    Test("保存后同种子重开应用全部参数，基线和重放使用相同配置", function()
        local seed = ctx.seed
        Edit(); Set("mobilizeAgricultureGrowth", "0.8"); Set("exploreAgricultureGrowth", "1.2")
        Set("naturalGrowthRate", "25"); Click("settingsMigration"); Set("migrationRate", "12")
        Click("settingsBack"); Click("settingsCompetition"); Set("explorePowerMultiplier", "1.25")
        Click("settingsBack"); Click("settingsSave"); Click("restartSameSeed")
        local cfg = ctx.world.config
        assert(ctx.seed == seed and ctx.world.generation == 0 and ctx.world.round == 0 and not ctx.modalOpen)
        assert(cfg.mobilizeAgricultureGrowth == .008 and cfg.exploreAgricultureGrowth == .012)
        assert(cfg.naturalGrowthRate == .25 and cfg.migrationRate == .12 and cfg.explorePowerMultiplier == 1.25)
        local expected = S.Baseline(seed, cfg)
        assert(ctx.baseline[#ctx.baseline].population == expected[#expected].population)
        assert(S.VerifyReplay(ctx.world))
        OriginDebug.Restart()
        assert(ctx.world.config.naturalGrowthRate == .25)
    end)
    Test("指定与随机种子重开均应用草稿，非法种子仍被拒绝", function()
        Edit(); Set("naturalGrowthRate", "35"); Click("settingsSave")
        Find("restartSeedInput"):SetValue("-1"); Click("restartWithSeed")
        assert(ctx.modalOpen and ctx.world.config.naturalGrowthRate == .25)
        Find("restartSeedInput"):SetValue("42"); Click("restartWithSeed")
        assert(ctx.seed == 42 and ctx.world.config.naturalGrowthRate == .35)
        Edit(); Set("naturalGrowthRate", "45"); Click("settingsSave"); Click("restartRandomSeed")
        assert(ctx.seed ~= 42 and ctx.world.config.naturalGrowthRate == .45)
    end)
    Test("自定义改良增幅与保护倍率反映在行动提示和帮助中", function()
        OriginDebug.Restart(15, {craftActionMultiplier = 1.275, protectionMultiplier = .4,
            mobilizeImprovementProbability = .256, exploreImprovementProbability = .256})
        assert(Find("regionLand"):GetText():find("25.6%%"))
        local action = Find("action_craft")
        action:OnPointerEnter({x = 0, y = 0, IsMouse = function() return true end})
        ctx.tips:Update(.5)
        assert(Find("buttonTip").children[1]:GetText():find("27.5%%"))
        assert(Find("buttonTip").children[1]:GetText():find("25.6%%"))
        local protect = Find("action_protect")
        protect:OnPointerEnter({x = 0, y = 0, IsMouse = function() return true end})
        ctx.tips:Update(.5)
        assert(Find("buttonTip").children[1]:GetText():find("0.4"))
    end)
    report.ok = report.failed == 0
    return report
end
return T
