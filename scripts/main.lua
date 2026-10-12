-- 基于官方 scaffold-2d.lua：Start → UI.Init → 数据 → 声明式界面 → Update。
local UI = require("urhox-libs/UI")
local Config = require("OriginConfig")
local Simulation = require("OriginSimulation")
local View = require("OriginView")
local Progress = require("OriginProgress")
local Evolution = require("OriginEvolution")

---@type table
local game = {
    world = {}, root = nil, baseline = {},
    seed = 20261002, phase = "decision", paused = false, speed = 1,
    layer = "quality", showRegions = true, showGrid = false, showMigration = true, showTechnology = true, action = "", ticksRemaining = 0,
    selectedIndex = 180, regionX = 10, regionY = 6, roundStart = 0, milestoneLevel = 0,
    accumulator = 0, tickAge = 0, modalOpen = false, tipsClosed = false,
    seenMigration = false, seenCompetition = false, seenProsperity = false,
    viewportW = 0, viewportH = 0,
}

local function SelectCell(x, y)
    game.selectedIndex = (y - 1) * game.world.config.width + x
    -- 点击边缘仍检查真实地块；干预框移至地图内，不裁成不完整区域。
    local maxX = game.world.config.width - game.world.config.regionSize + 1
    local maxY = game.world.config.height - game.world.config.regionSize + 1
    local half = game.world.config.regionSize // 2
    game.regionX = math.max(1, math.min(maxX, x - half))
    game.regionY = math.max(1, math.min(maxY, y - half))
    View.Refresh(game)
end

---@param seed integer?
---@param overrides table?
local function Restart(seed, overrides)
    local config = Simulation.ResolveConfig(overrides or game.world.config)
    if seed ~= nil then
        assert(math.tointeger(seed) and seed >= 0 and seed <= 2147483647, "地图种子必须为0～2147483647的整数")
        game.seed = seed
    end
    game.world = Simulation.New(game.seed, config)
    game.baseline = Simulation.Baseline(game.seed, config)
    game.localProgress = Progress.Local.New()
    game.phase = "decision"
    game.paused, game.action = false, ""
    game.milestoneLevel = 0
    game.ticksRemaining, game.accumulator, game.tickAge = 0, 0, 0
    Evolution.Reset(game)
    game.seenMigration, game.seenCompetition, game.seenProsperity = false, false, false
    game.viewportW, game.viewportH = 0, 0
    game.lastEventTitle, game.lastEventDetail = nil, nil
    game.selectedIndex = (8 - 1) * game.world.config.width + 12
    game.regionX, game.regionY = 12 - game.world.config.regionSize // 2, 8 - game.world.config.regionSize // 2
    View.Build(game)
    print(string.format("[重开] 种子%d 基准生活用品%.6f", game.seed, game.world.baselineCraft))
end

game.selectCell = SelectCell
game.restart = Restart

function Start()
    graphics.windowTitle = "富种起源 · 局部干预，观察涌现"
    input.mouseMode = MM_ABSOLUTE
    game.seed = Config.defaultSeed
    View.InitTheme()
    game.world = Simulation.New(game.seed)
    game.localProgress = Progress.Local.New()
    game.baseline = Simulation.Baseline(game.seed)
    game.selectedIndex = (8 - 1) * game.world.config.width + 12
    game.regionX, game.regionY = 12 - game.world.config.regionSize // 2, 8 - game.world.config.regionSize // 2
    View.Build(game)
    SubscribeToEvent("Update", "HandleUpdate")
    SubscribeToEvent("KeyDown", "HandleKeyDown")
    print(string.format("[启动] 富种起源 规则%s 种子%d 地块%d", tostring(Config.modelVersion), game.seed, #game.world.cells))
    print(string.format("[基准] 开局人均生活用品%.6f，繁荣门槛%.6f", game.world.baselineCraft, 2 * game.world.baselineCraft))
    print("[模拟] 固定顺序同步结算，动画独立于模拟随机数。")
end

function Stop()
    UnsubscribeFromAllEvents()
    UI.Shutdown()
end

local function AdvanceGeneration()
    local report = Evolution.Commit(game)
    game.ticksRemaining = game.ticksRemaining - 1
    game.tickAge = 0
    local summary = report.summary or Simulation.Statistics(game.world)
    View.OnGeneration(game)
    print(string.format("[世代%d] 人口%.3f 生活用品%.5f 探索%.2f%% 繁荣%.2f%% 流量%d 替代%d",
        game.world.generation, summary.population, summary.craftPerCapita,
        summary.exploreShare * 100, summary.prosperousShare * 100, #report.flows, #report.changes))
    if game.world.won or game.world.generation >= game.world.config.rounds * game.world.config.generationsPerRound then
        game.phase, game.paused = "ended", false
        View.RoundReport(game)
        View.Ending(game)
    elseif game.ticksRemaining <= 0 then
        game.phase, game.paused = "decision", false
        View.RoundReport(game)
    end
    View.Refresh(game)
end

---@param eventType string
---@param eventData UpdateEventData
function HandleUpdate(eventType, eventData)
    local dt = math.min(0.25, eventData:GetFloat("TimeStep"))
    View.Resize(game)
    View.UpdateTips(game, dt)
    if Evolution.IsPaused(game) then return end
    game.tickAge = game.tickAge + dt
    if game.phase ~= "simulation" then return end
    -- 先播放这代的真实流动，到终点才提交；提交帧不绘制下一代的流动。
    if Evolution.Update(game, dt) then
        AdvanceGeneration()
    end
end

---@param eventType string
---@param eventData KeyDownEventData
function HandleKeyDown(eventType, eventData)
    if game.portraitBlocked then return end
    local key = eventData:GetInt("Key")
    if game.modalOpen then
        if key == KEY_ESCAPE then
            View.ClosePanel(game)
        end
        return
    end
    if key == KEY_SPACE and game.phase == "simulation" then
        game.paused = not game.paused
        View.Refresh(game)
    elseif key == KEY_ESCAPE and game.phase == "decision" then
        game.action = ""
        View.Refresh(game)
    elseif key == KEY_H then
        View.Help(game)
    end
end

-- 供引擎离屏自动验收访问同一数据与操作，正式玩法不依赖此入口。
OriginDebug = {
    GetGame = function() return game end,
    Select = SelectCell,
    Choose = function(action) View.Choose(game, action) end,
    Confirm = function() View.Confirm(game) end,
    Advance = function()
        if game.phase == "simulation" and not Evolution.IsPaused(game) then AdvanceGeneration() end
    end,
    Restart = Restart,
    Help = function() View.Help(game) end,
    OpenPanel = function(kind) View.OpenPanel(game, kind) end,
    ClosePanel = function() View.ClosePanel(game) end,
}
