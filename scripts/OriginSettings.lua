-- 参数目录与草稿：独立于界面，不修改本局配置，也不消耗随机数。
local S = require("OriginSimulation")
local Defaults = require("OriginConfig")
local Settings = {fields = {}, byKey = {}}

local function Field(key, name, unit, low, high, tip, offset)
    local field = {key = key, name = name, unit = unit, min = low, max = high, tip = tip,
        scale = unit == "%" and 100 or 1, offset = offset or 0}
    Settings.fields[#Settings.fields + 1] = field
    Settings.byKey[key] = field
end

Field("mobilizeAgricultureGrowth", "动员型农业增长", "%", 0, 100, "每世代农业效率的自然增幅，按地块当时的制度计算；更多粮食也可能带来更多人口。")
Field("exploreAgricultureGrowth", "探索型农业增长", "%", 0, 100, "探索型地块每世代的农业效率增幅。只改变生产效率，不直接增加劳动占比。")
Field("mobilizeCraftGrowth", "动员型工艺增长", "%", 0, 100, "动员型地块每世代的工艺效率增幅。人口增长和劳动分配仍会影响人均用品。")
Field("exploreCraftGrowth", "探索型工艺增长", "%", 0, 100, "探索型地块每世代的工艺效率增幅；这是自动增长，不需要玩家执行改良。")
Field("mobilizeImprovementProbability", "动员型成功率", "%", 0, 100, "农业、工艺两类主动改良共用。按确认行动时的制度抽签；失败仍消耗本轮。")
Field("exploreImprovementProbability", "探索型成功率", "%", 0, 100, "探索型地块两类主动改良的成功率。0%必失败，100%必成功；保护不会提高成功率。")
Field("agricultureActionMultiplier", "农业改良增幅", "%", 0.01, 100, "仅改良成功时，将农业效率乘以（1＋此增幅）；不是增加农业劳动占比。", 1)
Field("craftActionMultiplier", "工艺改良增幅", "%", 0.01, 100, "仅改良成功时，将工艺效率乘以（1＋此增幅）；失败不产生这项增幅。", 1)
Field("technologyDiffusion", "地块间学习速率", "%", 0, 100, "每世代补齐自身与最先进四邻格之间的技术差距的这一比例，农业和工艺分别计算。50%表示学会差距的一半。")
Field("naturalGrowthSlope", "人口随粮食变化系数 k", "", 0, 10, "控制温饱线附近的人口反应速度。越大，略有余粮或短缺就越接近增长或减少上限；0表示关闭自然人口变化。")
Field("naturalGrowthRate", "人口净变化上限 r", "%", 0, 99, "每世代自然增长和减少共用的幅度上限，不含迁移。50%表示理论上接近＋50%或−50%，并非每世代固定增长50%。")
Field("culturalMixRate", "移民影响力系数 μ", "%", 0, 100, "控制迁入者改变当地农业劳动占比的力度，还要乘以迁入人口占比。不会直接带走或降低当地技术。")
Field("starvationPenalty", "缺粮惩罚 h", "", 0, 20, "效用中每单位缺粮的惩罚。越大，缺粮对迁移目的地选择的影响越强。")
Field("migrationResistance", "迁移阻力 b", "", 0, 10, "目的地效用必须比来源高出这一门槛，才有迁移意愿；越高，越不容易迁移。")
Field("migrationRate", "每世代迁出上限 m", "%", 0, 99, "来源人口每世代迁出的比例上限。真实流量还受效用差与地形限制，通常低于上限。")
Field("terrainPlainMigration", "平原通行效率", "%", 1, 100, "迁移边取两端地形通行效率的较小值。未迁出的人留在原地，不转分配到其他邻格。")
Field("terrainHillMigration", "丘陵通行效率", "%", 1, 100, "降低穿越丘陵的当世代迁移量，不额外设置途中等待世代。")
Field("terrainMountainMigration", "山地通行效率", "%", 1, 100, "降低穿越山地的当世代迁移量。河道不可定居，不作为迁移目的地。")
Field("craftPowerWeight", "用品竞争权重 w", "", 0, 10, "竞争实力中总生活用品的权重。提高后，工艺产出对制度竞争的贡献变大。")
Field("mobilizePowerMultiplier", "动员型实力倍率 a", "", 0.01, 10, "动员型地块的（总粮食＋加权总用品）乘以此倍率得到竞争实力。")
Field("explorePowerMultiplier", "探索型实力倍率 a", "", 0.01, 10, "探索型地块的实力倍率。越低越容易受强邻制度替代，但不直接影响生产效率。")
Field("replacementRate", "制度替代强度 q", "%", 0, 100, "乘以双方相对实力差，得到被最强异制度邻格替代的概率。0关闭制度替代，不关闭迁移。")
Field("protectionMultiplier", "保护时概率倍率 z", "%", 0, 100, "有保护时替代概率再乘此值；0完全防止替代，100%表示保护不减免替代风险。")
Field("replacementCultureRate", "替代后习惯混合 v", "%", 0, 100, "制度替代成功后，农业劳动占比向来源地块靠拢的比例；不直接复制技术。")

function Settings.Copy(config)
    local result = {}
    for key, value in pairs(config) do result[key] = value end
    return result
end

function Settings.New(config, editable)
    return {config = Settings.Copy(config), editable = editable == true, texts = {}, errors = {}}
end

function Settings.Display(config, key)
    local f = assert(Settings.byKey[key])
    return string.format("%.12g", (config[key] - f.offset) * f.scale)
end

function Settings.Set(session, key, text)
    if not session.editable then return false end
    local f = assert(Settings.byKey[key])
    session.texts[key] = text
    local number = tonumber(text)
    if not S.IsFinite(number) or number < f.min or number > f.max then
        session.errors[key] = string.format("%s：请输入 %g～%g%s", f.name, f.min, f.max, f.unit)
        return false
    end
    session.errors[key] = nil
    session.config[key] = number / f.scale + f.offset
    return true
end

function Settings.Error(session)
    for _, f in ipairs(Settings.fields) do
        if session.errors[f.key] then return session.errors[f.key] end
    end
end

function Settings.Validate(session)
    local errorText = Settings.Error(session)
    if errorText then return nil, errorText end
    local ok, config = pcall(S.ResolveConfig, session.config)
    if not ok then return nil, "参数组合无效：" .. tostring(config) end
    return config
end

function Settings.Reset(session)
    if not session.editable then return end
    for _, f in ipairs(Settings.fields) do session.config[f.key] = Defaults[f.key] end
    session.texts, session.errors = {}, {}
end

Settings.migrationFormula = {
    "s = A × f / (1 + N/K)；c = B × (1−f) / (1 + N/K)",
    "U = ln(1+c) − h × max(0, 1−s)",
    "d(i,j) = max(0, U(j)−U(i)−b)；D(i) = Σ邻格 d(i,j)",
    "O(i) = N(i) × m × D(i)/(1+D(i))",
    "M(i,j) = O(i) × d(i,j)/D(i) × min(t(i),t(j))",
    "N新 = N旧 − 迁出 + 迁入",
    "f新 = f旧 + μ × (迁入/N新) × (迁入者平均f − f旧)",
    "N：户数；K：地形修正后的承载量；A/B：农业/工艺效率；f：农业劳动占比；s：温饱比；c：人均用品；U：效用；t：地形通行效率。",
    "只看上下左右可居住邻格；D=0时不迁移。人口自然变化后统一计算流量，再同时结算；同一世代来者不会再次迁出。迁入者平均f按迁入人数加权。",
}
Settings.competitionFormula = {
    "F = N × s；C = N × c；P = a × (F + w × C)",
    "p = q × (P强−P自身)/(P强+P自身)",
    "有保护时：p保护 = p × z",
    "替代成功后：f新 = (1−v) × f自身 + v × f来源",
    "F/C：总粮食/总用品；P：竞争实力；a：本地制度实力倍率；w：用品竞争权重；q：替代强度；z：保护倍率；v：习惯混合比例。",
    "每世代技术增长与学习后，从四邻格中选最强者。仅当其更强且制度不同时才抽签替代；最强者并列时随机选一个。同制度强邻可能挡住异制度邻格。",
    "所有地块按同一快照竞争。替代不会直接复制来源技术；新制度从下一世代开始影响自然增长和主动改良成功率。保护仍按原有次数与持续时间使用。",
}

return Settings
