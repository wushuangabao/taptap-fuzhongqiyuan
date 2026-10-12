-- 在独立Lua运行时中用控件替身执行真实 main/View 回调；只验行为，不声称视觉验收。
local Tests = {}
function Tests.Run()
    local methods = {}
    function methods:AddChild(child) child.parent = self; self.children[#self.children + 1] = child end
    function methods:FindById(id)
        if self.props.id == id then return self end
        for _, child in ipairs(self.children) do
            local found = child:FindById(id)
            if found then return found end
        end
    end
    function methods:SetStyle(props) for key, value in pairs(props) do self.props[key] = value end end
    function methods:SetText(text) self.props.text = text end
    function methods:GetText() return self.props.text end
    function methods:SetDisabled(value) self.props.disabled = value end
    function methods:SetVisible(value) self.props.visible = value end
    function methods:SetValue(value) self.props.value = value end
    function methods:SetChecked(value) self.props.checked = value end
    function methods:SetFontColor(value) self.props.fontColor = value end
    function methods:ClearChildren() self.children = {} end
    function methods:Destroy()
        self.destroyed = true
        if self.parent then
            for i, child in ipairs(self.parent.children) do
                if child == self then table.remove(self.parent.children, i); break end
            end
        end
    end
    function methods:CancelGesture() end
    local function Widget(props) return setmetatable({props = props or {}, children = props and props.children or {}}, {__index = methods}) end
    local viewport = {w = 1280, h = 720}
    local ui = {Scale = {DEFAULT = 1}, Theme = {defaultTheme = {colors = {}}}, Toast = {count = 0}}
    for _, kind in ipairs({"Panel", "Label", "Button", "Row", "Column", "ScrollView", "SafeAreaView", "Divider", "ProgressBar", "Checkbox", "Slider"}) do ui[kind] = Widget end
    function ui.Theme.GetRegisteredTheme() return ui.Theme.defaultTheme end
    function ui.Theme.ExtendTheme(_, theme) return theme end
    function ui.Init() end
    function ui.SetRoot(root) ui.root = root end
    function ui.Shutdown() end
    function ui.GetScale() return 1 end
    function ui.GetViewportSize() return viewport.w, viewport.h end
    function ui.GetSafeAreaInsets() return {left = 0, right = 0, top = 0, bottom = 0} end
    function ui.Toast.Show() ui.Toast.count = ui.Toast.count + 1 end
    local widgets = {Colors = {}}
    for _, key in ipairs({"ink", "muted", "paper", "card", "line", "green", "gold", "teal", "red", "soil"}) do widgets.Colors[key] = {0, 0, 0, 255} end
    widgets.Icon, widgets.Chart = Widget, Widget
    function widgets.Map(props)
        local map = Widget(props)
        map.camera = {zoom = 1}
        return map
    end
    package.loaded["urhox-libs/UI"] = ui
    package.loaded.OriginWidgets = widgets
    package.loaded.OriginTips = {New = function()
        return {Hide = function() end, Update = function() end, Attach = function(_, widget) return widget end}
    end}
    graphics, input = {height = 720}, {}
    MM_ABSOLUTE = 0
    SubscribeToEvent = function() end
    local S = require("OriginSimulation")
    local P = require("OriginProgress")
    local View = require("OriginView")
    require("main")
    Start()
    local ctx = OriginDebug.GetGame()
    local report = {passed = 0, failed = 0, results = {}, ok = false}
    local function Test(name, run)
        local ok, err = pcall(run)
        report.results[#report.results + 1] = {name = name, passed = ok, error = not ok and tostring(err) or nil}
        if ok then report.passed = report.passed + 1 else report.failed = report.failed + 1 end
        print("[局部成果界面契约] " .. (ok and "通过 " or "失败 ") .. name .. (ok and "" or "：" .. tostring(err)))
    end
    local function Replacement()
        return {index = 1, from = 2, oldInstitution = "mobilize", newInstitution = "explore",
            foodShareBefore = 0.5, foodShareAfter = 0.5, sourceFoodShare = 0.5,
            probability = 1, roll = 0, protected = false}
    end
    Test("启动无虚构成果，原有地区详情保留", function()
        assert(#ctx.localProgress.history == 0 and not ctx.localProgress.pending)
        assert(ctx.root:FindById("cellRegionName") and ctx.root:FindById("cellRegionDescription"))
        OriginDebug.OpenPanel("trends")
        assert(ctx.root:FindById("localMilestoneHistory") and not ctx.root:FindById("localEvent_food"))
        OriginDebug.ClosePanel()
    end)
    Test("真实Confirm/Advance记录三类成果，移动选区不改原目标，无自动弹窗", function()
        ctx.world = S.New(ctx.seed, {naturalGrowthRate = 0, migrationRate = 0, replacementRate = 0, mobilizeAgricultureGrowth = 0, exploreAgricultureGrowth = 0,
            mobilizeImprovementProbability = 1, exploreImprovementProbability = 1}) -- 成果成功路径夹具
        for _, cell in ipairs(ctx.world.cells) do
            cell.population, cell.landCapacity, cell.agriculture, cell.foodShare, cell.craft = 40, 40, 3.9, 0.5, 2
            cell.institution = "mobilize"
        end
        S.RefreshMetrics(ctx.world)
        ctx.localProgress, ctx.phase, ctx.tipsClosed = P.Local.New(), "decision", true
        OriginDebug.Select(12, 8); OriginDebug.Choose("agriculture"); OriginDebug.Confirm()
        assert(ctx.localProgress.pending.region.x == 12 and ctx.localProgress.pending.region.size == 1 and ctx.phase == "simulation")
        OriginDebug.Select(20, 12); OriginDebug.Advance()
        assert(ctx.localProgress.completed.technology and not ctx.localProgress.completed.food and not ctx.modalOpen)
        for _ = 2, ctx.world.config.generationsPerRound do OriginDebug.Advance() end
        local foodEvent = ctx.localProgress.completed.food --[[@as OriginLocalEvent?]]
        assert(foodEvent and foodEvent.region.x == 12)
        OriginDebug.Select(12, 8); OriginDebug.Choose("institution"); OriginDebug.Confirm()
        for _ = 1, ctx.world.config.generationsPerRound do OriginDebug.Advance() end
        assert(ctx.localProgress.completed.exploration and #ctx.localProgress.history == 3 and not ctx.modalOpen)
    end)
    Test("日常语言主界面和完成历史同步，重复刷新不重复提示", function()
        local count, toasts = #ctx.localProgress.history, #ctx.notifications.items
        View.OnGeneration(ctx); View.Refresh(ctx)
        assert(#ctx.localProgress.history == count and #ctx.notifications.items == toasts)
        local text = ctx.root:FindById("nextGoal"):GetText()
        assert(text:find("局部成果") and not text:find("格"))
        OriginDebug.OpenPanel("trends")
        for _, kind in ipairs({"food", "technology", "exploration"}) do
            local title = ctx.root:FindById("localEvent_" .. kind):GetText()
            assert(not title:find("格"))
        end
        OriginDebug.ClosePanel()
    end)
    Test("小屏完成历史沿用原有滚动面板", function()
        viewport.w, viewport.h = 780, 420
        View.Resize(ctx)
        OriginDebug.OpenPanel("trends")
        assert(ctx.sheet.width <= viewport.w - 48 and ctx.sheet.height <= viewport.h - 48)
        assert(ctx.root:FindById("sheetScroll").props.scrollY and ctx.root:FindById("localMilestoneHistory"))
        OriginDebug.ClosePanel()
    end)
    Test("正式重开入口清除完成历史及候选，重新显示初始建议", function()
        OriginDebug.Restart()
        assert(#ctx.localProgress.history == 0 and not ctx.localProgress.pending and not ctx.localProgress.completed.food)
        assert(not ctx.root:FindById("nextGoal"):GetText():find("局部成果"))
    end)
    Test("跳过按钮丢弃已选行动和保护，只进入一次自然演进", function()
        OriginDebug.Restart()
        OriginDebug.Select(12, 8)
        OriginDebug.Choose("craft"); OriginDebug.Choose("protect")
        local before = {}
        for key, value in pairs(assert(ctx.world.cells[ctx.selectedIndex])) do before[key] = value end
        local protection = ctx.world.protectionLeft
        ctx.root:FindById("skipRound").props.onClick()
        assert(ctx.phase == "simulation" and ctx.world.round == 1 and ctx.world.generation == 0)
        assert(ctx.world.actions[1].action == "skip" and not ctx.world.actions[1].withProtection)
        assert(ctx.world.protectionLeft == protection and not ctx.localProgress.pending)
        for key, value in pairs(before) do assert(ctx.world.cells[ctx.selectedIndex][key] == value) end
        assert(ctx.root:FindById("skipRound").props.disabled and ctx.root:FindById("followRecommendation").props.disabled)
        ctx.root:FindById("skipRound").props.onClick(); ctx.root:FindById("followRecommendation").props.onClick()
        assert(ctx.world.round == 1)
        for _ = 1, ctx.world.config.generationsPerRound do OriginDebug.Advance() end
        assert(ctx.phase == "decision" and ctx.action == "" and #ctx.localProgress.history == 0)
        assert(not ctx.root:FindById("skipRound").props.disabled)
    end)
    Test("星标随选区刷新，推荐行动不会同时执行已选制度保护", function()
        OriginDebug.Restart()
        local R = require("OriginRecommendation")
        for _, xy in ipairs({{12, 8}, {20, 12}}) do
            OriginDebug.Select(xy[1], xy[2])
            local recommended = R.Choose(ctx.world, ctx.regionX, ctx.regionY)
            assert(ctx.recommendation == recommended)
            local count = 0
            for _, action in ipairs({"agriculture", "craft", "foodUp", "foodDown", "institution", "protect"}) do
                local badge = ctx.root:FindById("recommended_" .. action)
                assert(badge.props.pointerEvents == "none")
                if badge.props.visible then count = count + 1; assert(action == recommended) end
            end
            assert(count == 1)
        end
        OriginDebug.Choose("protect")
        local recommended, protection = ctx.recommendation, ctx.world.protectionLeft
        ctx.root:FindById("followRecommendation").props.onClick()
        local record = ctx.world.actions[1]
        assert(record.action == recommended and record.x == 20 and record.y == 12 and not record.withProtection)
        assert(ctx.phase == "simulation" and ctx.world.protectionLeft == protection)
        assert(ctx.localProgress.pending and ctx.localProgress.pending.action.action == recommended)
        for _, action in ipairs({"agriculture", "craft", "foodUp", "foodDown", "institution", "protect"}) do
            assert(not ctx.root:FindById("recommended_" .. action).props.visible)
        end
    end)
    Test("三按钮保留确认行为，弹窗与竖屏阻止推进，结束仍可查看结算", function()
        OriginDebug.Restart()
        assert(ctx.root:FindById("confirm").props.text == "确认所选行动" and ctx.root:FindById("confirm").props.disabled)
        ctx.modalOpen = true
        ctx.root:FindById("skipRound").props.onClick(); ctx.root:FindById("followRecommendation").props.onClick()
        assert(ctx.world.round == 0)
        ctx.modalOpen, ctx.portraitBlocked = false, true
        ctx.root:FindById("skipRound").props.onClick(); ctx.root:FindById("followRecommendation").props.onClick()
        assert(ctx.world.round == 0)
        ctx.portraitBlocked = false
        OriginDebug.Choose("craft")
        ctx.root:FindById("confirm").props.onClick()
        assert(ctx.world.actions[1].action == "craft" and ctx.phase == "simulation")
        ctx.phase = "ended"; View.Refresh(ctx)
        assert(ctx.root:FindById("skipRound").props.disabled and ctx.root:FindById("followRecommendation").props.disabled)
        assert(ctx.root:FindById("confirm").props.text == "查看结算" and not ctx.root:FindById("confirm").props.disabled)
    end)
    Test("正式成功率随所选制度更新，刷新不抽签", function()
        OriginDebug.Restart(nil, {}) -- 此项检查默认概率；普通重开现在会沿用当前配置。
        local state, draws = ctx.world.rng.state, ctx.world.rng.draws
        for _, institution in ipairs({"mobilize", "explore"}) do
            for _, cell in ipairs(ctx.world.cells) do
                if cell.institution == institution then
                    OriginDebug.Select(cell.x, cell.y)
                    local text = ctx.root:FindById("regionLand"):GetText()
                    assert(text:find(institution == "explore" and "30%%" or "10%%"))
                    break
                end
            end
        end
        assert(ctx.world.rng.state == state and ctx.world.rng.draws == draws)
    end)
    Test("真实确认显示改良成功或失败，失败也推进五世代且结果保留", function()
        for _, probability in ipairs({0, 1}) do
            for _, action in ipairs({"agriculture", "craft"}) do
                OriginDebug.Restart()
                ctx.world = S.New(ctx.seed, {mobilizeImprovementProbability = probability, exploreImprovementProbability = probability})
                OriginDebug.Select(12, 8); OriginDebug.Choose(action)
                ctx.root:FindById("confirm").props.onClick()
                local result = ctx.root:FindById("improvementResult"):GetText()
                assert(result:find(probability == 0 and "未成功" or "改良成功"))
                local name = action == "agriculture" and "农艺改良" or "工艺改良"
                local expected = probability == 0 and name .. "未成功" or
                    name .. "成功！地块效率 +" .. (action == "agriculture" and "12" or "15") .. "%"
                assert(ctx.notifications.items[1].message == expected, "通知使用简洁结果且不附加轮次、概率或保护说明")
                assert(ctx.phase == "simulation" and ctx.world.round == 1 and ctx.world.protectionLeft == 3)
                assert(ctx.root:FindById("confirm").props.disabled)
                for _ = 1, 5 do OriginDebug.Advance() end
                assert(ctx.phase == "decision" and ctx.world.generation == 5)
                assert(ctx.root:FindById("improvementResult"):GetText() == result)
                if probability == 0 then assert(not ctx.localProgress.completed.technology) end
            end
        end
        OriginDebug.Restart()
        assert(ctx.root:FindById("improvementResult"):GetText() == "改良失败仍消耗一轮。")
    end)
    Test("制度保护单独选择确认，与五种其他行动互斥且耗尽禁用", function()
        OriginDebug.Restart()
        for _, action in ipairs({"agriculture", "craft", "foodUp", "foodDown", "institution"}) do
            OriginDebug.Choose(action); OriginDebug.Choose("protect")
            assert(ctx.action == "protect" and ctx.world.protectionLeft == 3 and ctx.world.round == 0)
            OriginDebug.Choose(action)
            assert(ctx.action == action)
        end
        OriginDebug.Choose("protect"); OriginDebug.Choose("protect")
        assert(ctx.action == "" and ctx.world.protectionLeft == 3)
        local cell = ctx.world.cells[ctx.selectedIndex]
        local a, b, f, institution = cell.agriculture, cell.craft, cell.foodShare, cell.institution
        local draws = ctx.world.rng.draws
        OriginDebug.Choose("protect"); OriginDebug.Confirm()
        assert(ctx.world.actions[1].action == "protect" and not ctx.world.actions[1].withProtection)
        assert(ctx.world.round == 1 and ctx.world.protectionLeft == 2 and cell.protectionTicks == 5)
        assert(cell.agriculture == a and cell.craft == b and cell.foodShare == f and cell.institution == institution)
        assert(ctx.world.rng.draws == draws and #ctx.notifications.items == 0)
        OriginDebug.Confirm(); assert(ctx.world.round == 1 and ctx.world.protectionLeft == 2)
        for _ = 1, 5 do OriginDebug.Advance() end
        assert(ctx.phase == "decision" and ctx.world.cells[ctx.selectedIndex].protectionTicks == 0)
        ctx.world.protectionLeft = 0; View.Refresh(ctx)
        assert(ctx.root:FindById("action_protect").props.disabled)
    end)
    Test("世代迁移与制度替换独立触发，无轮末或流量门槛且每局一次", function()
        OriginDebug.Restart()
        ctx.tipsClosed, ctx.localProgress = false, nil
        ctx.world.maxProsperousShare = 0
        ctx.world.lastReport.totalMigration, ctx.world.lastReport.changes = 0, {}
        View.OnGeneration(ctx)
        assert(#ctx.notifications.items == 0)
        ctx.world.lastReport.totalMigration = 0.000001
        ctx.world.lastReport.changes = {Replacement()}
        View.OnGeneration(ctx)
        local items = ctx.notifications.items
        assert(#items == 2 and items[1].panel and items[2].panel)
        assert(items[1].message == "居民向生活更好的相邻地块迁移，会将原本的习惯带到当地。")
        assert(items[2].message == "竞争力强的地块，其制度会向周边传播。")
        View.OnGeneration(ctx); View.RoundReport(ctx)
        assert(ctx.seenMigration and ctx.seenCompetition)
        local count = #items
        View.OnGeneration(ctx); View.RoundReport(ctx)
        assert(#items == count, "重复回调不重复触发")
        OriginDebug.Restart()
        assert(not ctx.seenMigration and not ctx.seenCompetition and not ctx.seenProsperity)
    end)
    Test("一个低于2%人口的繁荣地块在轮末触发，不在世代中间触发", function()
        OriginDebug.Restart()
        ctx.tipsClosed, ctx.localProgress = false, nil
        for _, cell in ipairs(ctx.world.cells) do cell.craft = 0.000001 end
        S.RefreshMetrics(ctx.world)
        View.RoundReport(ctx)
        assert(not ctx.seenProsperity and #ctx.notifications.items == 0)
        local cell = ctx.world.cells[ctx.selectedIndex]
        cell.agriculture, cell.craft = 1000, 1000
        S.RefreshMetrics(ctx.world)
        local stats = S.Statistics(ctx.world)
        assert(stats.prosperousShare > 0 and stats.prosperousShare < 0.02)
        ctx.world.lastReport.totalMigration, ctx.world.lastReport.changes = 1, {Replacement()}
        ctx.world.maxProsperousShare = 0
        View.OnGeneration(ctx)
        assert(#ctx.notifications.items == 2 and not ctx.seenProsperity)
        View.RoundReport(ctx)
        assert(#ctx.notifications.items == 3 and ctx.seenProsperity)
        assert(ctx.notifications.items[3].message == "繁荣出现了！满足温饱的同时，生活用品也达到人均富足。")
        View.RoundReport(ctx)
        assert(#ctx.notifications.items == 3)
    end)
    Test("三个里程碑通知统一文案，衰退再达标不重复", function()
        OriginDebug.Restart()
        ctx.localProgress, ctx.tipsClosed = nil, true
        for i, share in ipairs({0.10, 0.30, 0.60}) do
            ctx.world.maxProsperousShare = share
            View.OnGeneration(ctx)
            assert(ctx.notifications.items[i].message == string.format("里程碑：已有%.0f%%人口达到繁荣", share * 100))
        end
        ctx.world.maxProsperousShare = 0.30; View.OnGeneration(ctx)
        ctx.world.maxProsperousShare = 0.60; View.OnGeneration(ctx)
        assert(#ctx.notifications.items == 3)
    end)
    Test("多通知独立8秒，悬停只暂停当前通知，暂停或面板冻结全部计时", function()
        OriginDebug.Restart()
        local manager = ctx.notifications --[[@as table]]
        local first, second = manager:Show("第一条"), manager:Show("第二条")
        assert(first.panel and second.panel and #manager.stack.children == 2)
        assert(first.remaining == 8 and second.remaining == 8)
        View.UpdateTips(ctx, 1)
        first.panel.props.onPointerEnter({IsMouse = function() return true end})
        View.UpdateTips(ctx, 2)
        assert(first.remaining == 7 and second.remaining == 5)
        ctx.paused = true; View.UpdateTips(ctx, 100); ctx.paused = false
        assert(first.remaining == 7 and second.remaining == 5)
        ctx.modalOpen = true; View.UpdateTips(ctx, 100); ctx.modalOpen = false
        assert(first.remaining == 7 and second.remaining == 5)
        assert(first.progress.props.value == 7 / 8 and second.progress.props.value == 5 / 8)
        ctx.portraitBlocked = true; View.UpdateTips(ctx, 100); ctx.portraitBlocked = false
        assert(first.remaining == 7 and second.remaining == 5)
        first.panel.props.onPointerLeave({IsMouse = function() return true end})
        View.UpdateTips(ctx, 5)
        assert(#manager.items == 1 and manager.items[1] == first and first.remaining == 2)
        assert(#manager.stack.children == 1)
        View.UpdateTips(ctx, 2)
        assert(#manager.items == 0 and #manager.stack.children == 0)
    end)
    Test("新提示不强制移除悬停中的旧提示，关闭新手提示不影响其他通知", function()
        OriginDebug.Restart()
        ctx.tipsClosed, ctx.localProgress = false, nil
        local manager = ctx.notifications --[[@as table]]
        local tutorial = manager:Show("新手说明", {category = "tutorial"})
        tutorial.hovered = true
        for i = 1, 6 do manager:Show("行动结果" .. i) end
        assert(#manager.items == 7 and not tutorial.panel.destroyed)
        View.Help(ctx)
        local function FindCheckbox(widget)
            if widget.props.label == "关闭新手提示" then return widget end
            for _, child in ipairs(widget.children) do
                local found = FindCheckbox(child)
                if found then return found end
            end
        end
        local checkbox = assert(FindCheckbox(ctx.root))
        checkbox.props.onChange(checkbox, true)
        assert(ctx.tipsClosed and #manager.items == 6 and tutorial.panel.destroyed)
        View.ClosePanel(ctx)
        ctx.world.lastReport.totalMigration, ctx.world.lastReport.changes = 1, {Replacement()}
        ctx.world.maxProsperousShare = 0
        View.OnGeneration(ctx); View.RoundReport(ctx)
        assert(#manager.items == 6 and not ctx.seenMigration and not ctx.seenCompetition)
        OriginDebug.Restart()
        assert(ctx.tipsClosed and #ctx.notifications.items == 0)
    end)
    report.ok, report.total = report.failed == 0, #report.results
    return report
end
return Tests
