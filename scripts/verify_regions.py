"""Verify regional terrain maps using the real Lua 5.4 model; preserve older evidence.

Use Python 3.11 with lupa 2.8 in .tmp/winability-deps.
"""
import argparse
import concurrent.futures
import hashlib
import json
from pathlib import Path
import sys
import time
sys.dont_write_bytecode = True

from verify_winability import runtime, plain, run_job

ROOT = Path(__file__).resolve().parents[1]
SOURCES = ['OriginConfig.lua', 'OriginSimulation.lua', 'OriginRegions.lua', 'OriginRegionLayout.lua',
           'OriginWidgets.lua', 'OriginView.lua', 'OriginTests.lua', 'OriginRegionsTests.lua',
           'OriginRegionIntegrationTests.lua', 'OriginWinability.lua', 'verify_regions.py',
           'OriginTerrain.lua', 'OriginTerrainTests.lua', 'OriginTerrainIntegrationTests.lua',
           'OriginGridIntegrationTests.lua']


def source_hashes():
    return {name: hashlib.sha256((ROOT/'scripts'/name).read_bytes()).hexdigest() for name in SOURCES}


def verify_result(result):
    lua = runtime()
    return lua.execute("return require('OriginWinability').Verify(...)", lua.table_from(result, recursive=True))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--seeds', type=int, default=20)
    parser.add_argument('--workers', type=int, default=4)
    parser.add_argument('--policies', nargs='+', default=['balanced', 'craft_spread', 'institution_strong'])
    args = parser.parse_args()
    assert args.seeds > 0
    started = time.monotonic()
    source_before = source_hashes()
    lua = runtime()
    tests = {name: plain(lua.execute(f"return require('{name}').Run()")) for name in
             ['OriginTests', 'OriginRegionsTests', 'OriginRegionIntegrationTests',
              'OriginTerrainTests', 'OriginTerrainIntegrationTests', 'OriginGridIntegrationTests']}
    assert all(result['ok'] for result in tests.values()), tests
    world = lua.execute("return require('OriginSimulation').New()")
    terrain_counts = {kind: sum(c.terrainKind == kind for c in world.cells.values())
                      for kind in ['plain', 'hill', 'mountain']}
    region_stats = []
    for region in world.regions.values():
        indices = list(region.indices.values())
        cells = [world.cells[i] for i in indices]
        total = sum(c.population for c in cells)
        region_stats.append(dict(name=region.name, kind=region.kind, cells=len(cells), population=total,
            averageCapacity=sum(c.landCapacity for c in cells)/len(cells),
            averageAgriculture=sum(c.agriculture for c in cells)/len(cells),
            averageCraft=sum(c.craft for c in cells)/len(cells),
            foodRatio=sum(world.metrics[i].food for i in indices)/total if total > 0 else 0,
            craftPerCapita=sum(world.metrics[i].craft for i in indices)/total if total > 0 else 0))
    seeds = [20261002] + [1 + i * 104729 for i in range(args.seeds - 1)]
    jobs = [(seed, policy, 17) for seed in seeds for policy in ['baseline'] + args.policies]
    results = []
    with concurrent.futures.ProcessPoolExecutor(max_workers=args.workers) as pool:
        for result in pool.map(run_job, jobs):
            results.append(result)
            if len(results) % 10 == 0:
                print(f"Verified {len(results)}/{len(jobs)} games", flush=True)
        # Every win is replayed with complete per-cell history in its own Lua runtime.
        winning = [r for r in results if r['won'] and r['policy'] != 'baseline']
        for i, (result, verified) in enumerate(zip(winning, pool.map(verify_result, winning)), 1):
            result['verifiedFullReplay'] = verified
            if i % 10 == 0:
                print(f"Replayed {i}/{len(winning)} winning games", flush=True)
    wins = {policy: sum(r['won'] for r in results if r['policy'] == policy)
            for policy in ['baseline'] + args.policies}
    # All curves were checked above; retain default-map curves plus every seed/action record.
    for result in results:
        if result['seed'] != 20261002:
            result.pop('curve', None)
    assert source_before == source_hashes(), 'Source changed during verification; rerun against stable files'
    evidence = dict(date='2026-10-08', modelVersion=world.config.modelVersion, config=plain(world.config),
        geographyVersion=world.geographyVersion, luaVersion=lua.eval('_VERSION'),
        terrainVersion=world.terrainVersion,
        terrainCounts=terrain_counts,
        terrain=plain(lua.execute("return require('OriginTerrain').Generate(...)", 20261002)),
        tests=tests, seeds=seeds, policies=args.policies, wins=wins, results=results,
        regions=region_stats, geography=dict(version=world.geographyVersion,
            regions=plain(world.regions), cellRegionIds=plain(world.cellRegionIds)),
        runtimeVisualAcceptance='UNDETERMINED: no runtime visual acceptance in this test',
        sourceSha256=source_before,
        elapsedSeconds=time.monotonic()-started)
    out = ROOT/'.tmp/verification/regions/land-v17-results.json'
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(evidence, ensure_ascii=False, indent=2), encoding='utf-8')
    print(json.dumps(dict(tests=sum(t['passed'] for t in tests.values()), games=len(results), wins=wins,
                         seconds=evidence['elapsedSeconds']), ensure_ascii=False), flush=True)


if __name__ == '__main__':
    main()
