"""Isolated balance proposals: override per-world config; never write OriginConfig.lua."""
import concurrent.futures
import argparse
import hashlib
import json
from pathlib import Path
import sys
import subprocess

sys.dont_write_bytecode = True
from verify_winability import ROOT, plain, runtime

SCENARIOS = {
    'current': {},
    'area5': {'regionSize': 5},
    'area5_time140': {'regionSize': 5, 'generationsPerRound': 7},
    'area5_time200': {'regionSize': 5, 'generationsPerRound': 10},
    'area5_time200_migration04': {'regionSize': 5, 'generationsPerRound': 10, 'migrationRate': .04},
    'area5_time200_agri004': {'regionSize': 5, 'generationsPerRound': 10, 'mobilizeAgricultureGrowth': .004, 'exploreAgricultureGrowth': .004},
    'area5_time200_food98': {'regionSize': 5, 'generationsPerRound': 10, 'prosperousFoodRatio': .98},
    'area7_time160': {'regionSize': 7, 'generationsPerRound': 8},
    'area7_time200': {'regionSize': 7, 'generationsPerRound': 10},
    'small16_time200': {'width': 16, 'height': 10, 'generationsPerRound': 10},
    'small12_time160': {'width': 12, 'height': 8, 'generationsPerRound': 8},
    'small12_time200': {'width': 12, 'height': 8, 'generationsPerRound': 10},
}

SECOND_STAGE = {
    'area7_time160_migration04': {'regionSize': 7, 'generationsPerRound': 8, 'migrationRate': .04},
    'area7_time160_food98': {'regionSize': 7, 'generationsPerRound': 8, 'prosperousFoodRatio': .98},
    'area7_time160_agri004': {'regionSize': 7, 'generationsPerRound': 8, 'mobilizeAgricultureGrowth': .004, 'exploreAgricultureGrowth': .004},
    'area5_time200_goal40': {'regionSize': 5, 'generationsPerRound': 10, 'victoryShare': .4},
    'area5_time200_diffuse05': {'regionSize': 5, 'generationsPerRound': 10, 'experimentalDiffusion': .05},
    'area5_time160_diffuse05': {'regionSize': 5, 'generationsPerRound': 8, 'experimentalDiffusion': .05},
    'area5_time200_diffuse10': {'regionSize': 5, 'generationsPerRound': 10, 'experimentalDiffusion': .10},
}


def experiment(job):
    name, config, seed, policy = job
    lua = runtime()
    # Preserve the v1.0 baseline for historical proposals. Use built-in diffusion once.
    config = {'regionSize': 3, 'generationsPerRound': 5, 'protectionDuration': 5,
              'technologyDiffusion': 0, **config}
    diffusion = config.pop('experimentalDiffusion', 0)
    config['technologyDiffusion'] = diffusion
    result = plain(lua.execute("return require('OriginWinability').Run(...)", seed, policy, 17, None,
                               lua.table_from(config)))
    if result['won'] and policy != 'baseline':
        result['verifiedFullReplay'] = lua.execute("return require('OriginWinability').Verify(...)",
                                                  lua.table_from(result, recursive=True))
    return {'scenario': name, 'experimentalDiffusion': diffusion, **result}


def save_results(path, scenarios, results):
    compact = [{k: v for k, v in r.items() if k != 'curve' or
                (r['seed'] == 20261002 and r['policy'] == 'balanced')} for r in results]
    summary = {}
    for name in scenarios:
        summary[name] = {}
        for policy in ['baseline', 'random', 'craft_spread', 'institution_strong', 'balanced']:
            subset = [r for r in results if r['scenario'] == name and r['policy'] == policy]
            wins = [r for r in subset if r['won']]
            summary[name][policy] = {'runs': len(subset), 'wins': len(wins),
                'winningGenerations': [r['generation'] for r in wins],
                'peakMin': min(r['peak'] for r in subset), 'peakMax': max(r['peak'] for r in subset)}
    path.write_text(json.dumps({'date': '2026-10-04', 'experimentalOnly': True, 'scenarios': scenarios,
        'sourceSha256': {name: hashlib.sha256((ROOT/'scripts'/name).read_bytes()).hexdigest()
                         for name in ['OriginConfig.lua', 'OriginSimulation.lua']},
        'summary': summary, 'results': compact}, ensure_ascii=False, indent=2), encoding='utf8')


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--stage2', action='store_true')
    parser.add_argument('--confirm', action='store_true', help='20-seed validation of two winning proposals')
    args = parser.parse_args()
    name = ('balance-proposals-confirmed.json' if args.confirm else
            'balance-experiments-stage2.json' if args.stage2 else 'balance-experiments.json')
    path = ROOT / '.tmp/verification/balance' / name
    subprocess.run(['git', 'check-ignore', '--quiet', str(path)], cwd=ROOT, check=True)
    path.parent.mkdir(parents=True, exist_ok=True)
    scenarios = ({name: SECOND_STAGE[name] for name in
                  ('area7_time160_migration04', 'area5_time160_diffuse05')}
                 if args.confirm else SECOND_STAGE if args.stage2 else SCENARIOS)
    policies = ['baseline', 'random', 'craft_spread', 'institution_strong', 'balanced']
    seeds = [20261002] + [1 + i * 104729 for i in range(19)] if args.confirm else [20261002, 1, 104730]
    jobs = [(name, config, seed, policy) for name, config in scenarios.items()
            for seed in seeds for policy in policies]
    results = []
    with concurrent.futures.ProcessPoolExecutor(max_workers=4) as pool:
        for result in pool.map(experiment, jobs):
            results.append(result)
            if len(results) % 15 == 0:
                subset = results[-15:]
                print(result['scenario'], 'peak', round(max(r['peak'] for r in subset)*100, 2),
                      'wins', [(r['seed'], r['policy'], r['generation']) for r in subset if r['won']], flush=True)
    save_results(path, scenarios, results)


if __name__ == '__main__':
    main()
