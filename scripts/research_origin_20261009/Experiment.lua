-- Isolated research harness. Production modules, parameters and recommendation are read-only.
local S = require('OriginSimulation')
local W = require('OriginWinability')
local R = require('OriginRecommendation')
local E = {}

local function copy(v)
    if type(v) ~= 'table' then return v end
    local out = {}; for k,x in pairs(v) do out[k] = copy(x) end; return out
end

local function strongest(world, x1, x2, y1, y2)
    local best, score = nil, -math.huge
    for i,c in ipairs(world.cells) do
        if c.x >= x1 and c.x <= x2 and c.y >= y1 and c.y <= y2 then
            local p = world.metrics[i].power
            if p > score then best,score = i,p end
        end
    end
    return best
end

local function setup(world)
    local w,h = world.width,world.height
    return {strong = strongest(world,1,w,1,h), hubs={
        strongest(world,1,w//2,1,h//2), strongest(world,w//2+1,w,1,h//2),
        strongest(world,1,w//2,h//2+1,h), strongest(world,w//2+1,w,h//2+1,h)},
        rng=S.NewRandom(17)}
end

local function target(world, state, selector)
    local turn=world.round+1
    if selector=='center' then return (world.height//2-1)*world.width+world.width//2 end
    if selector=='scan' then return ((turn-1) % #world.cells)+1 end
    if selector=='strong' then return state.strong end
    if selector=='hubs' then return state.hubs[(turn-1)%4+1] end
    error('unknown selector '..tostring(selector))
end

local function spatialReform(world)
    local best, highest = nil,-math.huge
    for i,c in ipairs(world.cells) do
        if c.institution ~= 'explore' then
            local neighbor = 0
            for _,j in ipairs(world.neighbors[i]) do neighbor=math.max(neighbor,world.metrics[j].power) end
            local survival = math.min(1,0.75*world.metrics[i].power/math.max(1e-9,neighbor))
            local distance=world.width+world.height
            for _,o in ipairs(world.cells) do
                if o.institution=='explore' then distance=math.min(distance,math.abs(c.x-o.x)+math.abs(c.y-o.y)) end
            end
            local score=c.population*survival^4*math.min(1,distance/5)
            if score>highest then best,highest=i,score end
        end
    end
    return best
end

local function addon(world,a,mode)
    if world.protectionLeft<=0 or a.action=='skip' then return a end
    if mode=='first' then a.withProtection=true; return a end
    if mode=='risk' then
        local i=(a.y-1)*world.width+a.x
        local cell=copy(world.cells[i]); if a.action=='institution' then cell.institution='explore' end
        if cell.institution=='explore' then
            local p=S.Metrics(cell,world.config).power
            local highest,other=0,false
            for _,j in ipairs(world.neighbors[i]) do
                local m=world.metrics[j]
                if m.power>highest then highest,other=m.power,world.cells[j].institution~='explore' end
            end
            if other and highest>p then a.withProtection=true end
        end
    end
    return a
end

function E.Choose(world,state,policy)
    if policy=='baseline' then return {action='skip',x=1,y=1} end
    local threshold=policy:match('^core(%d+)$')
    if threshold then
        local i=target(world,state,'center'); local c=world.cells[i]
        return {action=world.metrics[i].foodRatio<tonumber(threshold)/100 and 'agriculture' or 'craft',x=c.x,y=c.y}
    end
    local kind,selector=policy:match('^(craft)_(center)$')
    if not kind then kind,selector=policy:match('^(rec)_(center)$') end
    if not kind then kind,selector=policy:match('^(craft)_(scan)$') end
    if not kind then kind,selector=policy:match('^(rec)_(scan)$') end
    if not kind then kind,selector=policy:match('^(craft)_(strong)$') end
    if not kind then kind,selector=policy:match('^(rec)_(strong)$') end
    if not kind then kind,selector=policy:match('^(craft)_(hubs)$') end
    if not kind then kind,selector=policy:match('^(rec)_(hubs)$') end
    if kind then
        local c=world.cells[target(world,state,selector)]
        return {action=kind=='rec' and R.Choose(world,c.x,c.y) or 'craft',x=c.x,y=c.y}
    end
    if policy=='balanced_protect' then return addon(world,W.Choose(world,'balanced',state.rng),'first') end
    if policy=='balanced_risk' then return addon(world,W.Choose(world,'balanced',state.rng),'risk') end
    if policy=='network' or policy=='network_risk' or policy=='network_skip' then
        local a
        if world.round<30 then
            local i=spatialReform(world)
            if i then local c=world.cells[i]; a={action='institution',x=c.x,y=c.y} end
        end
        a=a or W.Choose(world,'balanced',state.rng)
        if policy=='network_skip' and world.round>=30 then a={action='skip',x=1,y=1} end
        return policy=='network_risk' and addon(world,a,'risk') or a
    end
    if policy=='reform30_skip' and world.round>=30 then return {action='skip',x=1,y=1} end
    if policy=='reform30_skip' then return W.Choose(world,'institution_strong',state.rng) end
    return W.Choose(world,policy,state.rng)
end

function E.Opening(seed)
    local world=S.New(seed)
    local rng=copy(world.rng)
    local counts={}; local records={}
    for i,c in ipairs(world.cells) do
        local a=R.Choose(world,c.x,c.y)
        counts[a]=(counts[a] or 0)+1
        records[i]={cell=copy(c),metric=copy(world.metrics[i]),recommendation=a,regionId=world.cellRegionIds[i]}
    end
    assert(rng.state==world.rng.state and rng.draws==world.rng.draws)
    return {seed=seed,baselineCraft=world.baselineCraft,counts=counts,cells=records,
        regions=world.regions,explorationAreas=world.explorationAreas,selectors=setup(world)}
end

function E.Run(seed,policy,verify,plan)
    local world=S.New(seed); local state=setup(world)
    local curve={copy(world.history[1].summary)}; local decisions={}
    local peak,peakGeneration,bestFive,maxStreak,maxMigrationError=0,0,0,0,0
    local milestones={}; local longest=0
    for turn=1,world.config.rounds do
        local a=plan and plan[turn] or E.Choose(world,state,policy)
        local i=(a.y-1)*world.width+a.x
        local c,m=world.cells[i],world.metrics[i]
        local neighbors={}
        for _,j in ipairs(assert(world.neighbors[i])) do
            neighbors[#neighbors+1]={index=j,x=world.cells[j].x,y=world.cells[j].y,
                population=world.cells[j].population,institution=world.cells[j].institution,
                power=world.metrics[j].power,food=world.metrics[j].foodRatio,craft=world.metrics[j].craftPerCapita}
        end
        decisions[turn]={action=copy(a),before=copy(c),metric=copy(m),neighbors=neighbors,
            recommended=R.Choose(world,a.x,a.y),summary=copy(S.Statistics(world))}
        local ok,reason=S.ApplyAction(world,a.action,a.x,a.y,a.withProtection); assert(ok,reason)
        for _=1,world.config.generationsPerRound do
            local report=S.Tick(world); local s=report.summary
            maxMigrationError=math.max(maxMigrationError,math.abs(report.migrationConservationError))
            assert(maxMigrationError<1e-7)
            curve[#curve+1]=copy(s)
            if s.prosperousShare>peak then peak,peakGeneration=s.prosperousShare,s.generation end
            maxStreak=math.max(maxStreak,s.prosperousStreak)
            for _,t in ipairs({0.1,0.3,0.6,0.8}) do
                if not milestones[tostring(t)] and s.prosperousShare>=t then milestones[tostring(t)]=s.generation end
            end
            if #curve>=6 then
                local floor=1
                for n=#curve-4,#curve do floor=math.min(floor,curve[n].prosperousShare) end
                bestFive=math.max(bestFive,floor)
            end
            if not verify then world.history={report} end
            if world.won then break end
        end
        decisions[turn].after=copy(world.cells[i]); decisions[turn].afterMetric=copy(world.metrics[i])
        decisions[turn].afterSummary=copy(S.Statistics(world))
        if world.won then break end
    end
    local verified=false
    if verify then local ok,reason=S.VerifyReplay(world); assert(ok,reason); verified=true end
    local out={seed=seed,policy=policy,won=world.won,generation=world.generation,round=world.round,
        firstWinGeneration=world.won and world.generation or false,peak=peak,peakGeneration=peakGeneration,
        bestFive=bestFive,maxStreak=maxStreak,final=S.Statistics(world),curve=curve,actions=world.actions,
        decisions=decisions,milestones=milestones,maxMigrationError=maxMigrationError,
        verifiedFullReplay=verified,finalCells=world.cells,finalRng=world.rng,selectors=state}
    return out
end

return E
