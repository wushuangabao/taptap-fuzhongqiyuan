"""Sample the formal simulation for glyph quantization; never change its rules.

Run with the same Lua 5.4 dependency as verify_winability.py. Sampling is cached
under .tmp, with source hashes checked before reuse; evidence is saved separately.
"""
import bisect
import concurrent.futures
import hashlib
import json

from verify_winability import ROOT, plain, runtime

CACHE = ROOT / '.tmp/verification/cell-visuals/cell-visual-samples.json'
OUTPUT = ROOT / '.tmp/verification/cell-visuals/cell-visuals-thresholds-distribution.json'
MODEL = ['OriginConfig.lua', 'OriginSimulation.lua', 'OriginRegions.lua',
         'OriginTerrain.lua', 'OriginLocalMilestones.lua', 'OriginWinability.lua']


def hashes():
    return {name: hashlib.sha256((ROOT / 'scripts' / name).read_bytes()).hexdigest() for name in MODEL}


def sample(job):
    seed, policy = job
    lua = runtime()
    rows = plain(lua.execute('''
        local S, W = require('OriginSimulation'), require('OriginWinability')
        local seed, policy = ...
        local world, rng = S.New(seed), S.NewRandom(17)
        local rows = {}
        local function snapshot(round)
            for i, c in ipairs(world.cells) do
                local m = world.metrics[i]
                rows[#rows + 1] = {round, m.foodRatio, m.craftPerCapita / world.baselineCraft, c.population}
            end
        end
        snapshot(0)
        for round = 1, world.config.rounds do
            if policy ~= 'baseline' then
                local a = W.Choose(world, policy, rng)
                assert(S.ApplyAction(world, a.action, a.x, a.y, a.withProtection))
            end
            for _ = 1, world.config.generationsPerRound do
                local report = S.Tick(world)
                world.history = {report}
                if world.won then break end
            end
            snapshot(round)
            if world.won then break end
        end
        return rows
    ''', seed, policy))
    return dict(seed=seed, policy=policy, rows=rows)


def summarize(rows, thresholds):
    values = sorted(row[1] for row in rows)
    bins = [0] * (len(thresholds) + 1)
    for value in values:
        bins[bisect.bisect_right(thresholds, value + 1e-9)] += 1
    return dict(samples=len(rows), foodLevels=list(range(len(bins))), foodCounts=bins,
                foodPercent=[round(n / len(rows) * 100, 2) for n in bins],
                quantiles={str(p): values[round((len(values) - 1) * p / 100)]
                           for p in [0, 1, 5, 10, 25, 50, 75, 90, 95, 99, 100]},
                roseCapPercent=round(sum(row[2] + 1e-9 >= 3 for row in rows) / len(rows) * 100, 2),
                houseCapPercent=round(sum(row[3] > 75 for row in rows) / len(rows) * 100, 2))


def main():
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    before = hashes()
    if CACHE.exists():
        cache = json.loads(CACHE.read_text(encoding='utf-8'))
        assert cache['sourceSha256'] == before, 'Model changed: remove stale sample cache before resampling'
    else:
        seeds = [20261002, 1, 104730, 209459, 314188]
        policies = ['baseline', 'balanced', 'agriculture_spread', 'craft_spread', 'random']
        jobs = [(seed, policy) for seed in seeds for policy in policies]
        with concurrent.futures.ProcessPoolExecutor(max_workers=4) as pool:
            runs = []
            for result in pool.map(sample, jobs):
                runs.append(result)
                print(f"Sampled {len(runs)}/{len(jobs)}", flush=True)
        assert hashes() == before, 'Model changed while sampling'
        cache = dict(sourceSha256=before, seeds=seeds, policies=policies, runs=runs)
        CACHE.write_text(json.dumps(cache, separators=(',', ':')), encoding='utf-8')
    # Read the actual fixed scale, including the zero-block interval.
    lua = runtime()
    thresholds = plain(lua.execute("return require('OriginCellVisuals').FoodThresholds"))
    rows = [row for run in cache['runs'] for row in run['rows']]
    report = dict(sourceSha256=before, seeds=cache['seeds'], policies=cache['policies'],
                  choiceSeed=17, runs=len(cache['runs']), thresholds=thresholds,
                  sampling='Every cell at opening and each round end; stop on victory. Repeated cell-round observations, not human play.',
                  glyphSourceSha256=hashlib.sha256((ROOT / 'scripts/OriginCellVisuals.lua').read_bytes()).hexdigest(),
                  overall=summarize(rows, thresholds),
                  stages={stage: summarize([r for r in rows if low <= r[0] <= high], thresholds)
                          for stage, low, high in [('opening', 0, 0), ('early', 1, 5), ('middle', 6, 12), ('late', 13, 20)]},
                  byPolicy={policy: summarize([r for run in cache['runs'] if run['policy'] == policy for r in run['rows']], thresholds)
                            for policy in cache['policies']})
    OUTPUT.write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print(json.dumps(report, ensure_ascii=False), flush=True)


if __name__ == '__main__':
    main()
