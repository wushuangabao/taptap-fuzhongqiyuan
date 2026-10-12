"""Run the unmodified game model using lupa.lua54; save reproducible JSON evidence.

python -m pip install --target .tmp/winability-deps lupa==2.8
python scripts/verify_winability.py
"""
import argparse
import concurrent.futures
import hashlib
import json
import random
from pathlib import Path
import sys
import time
sys.dont_write_bytecode = True

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / '.tmp/winability-deps'))


def runtime():
    from lupa.lua54 import LuaRuntime
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.globals().script_dir = (ROOT / 'scripts').as_posix()
    lua.execute("package.path = script_dir .. '/?.lua;' .. package.path")
    return lua


def plain(value):
    if hasattr(value, 'items'):
        pairs = dict(value.items())
        if pairs and all(isinstance(k, int) for k in pairs) and set(pairs) == set(range(1, len(pairs) + 1)):
            return [plain(pairs[i]) for i in range(1, len(pairs) + 1)]
        return {str(k): plain(v) for k, v in pairs.items()}
    return value


def run_job(job):
    seed, policy, choice_seed, *extra = job
    lua = runtime()
    plan = lua.table_from(extra[0], recursive=True) if extra else None
    try:
        return plain(lua.execute("return require('OriginWinability').Run(...)", seed, policy, choice_seed, plan))
    except Exception as error:
        # Only action-legality failures are expected search rejections. Never hide model/runtime failures.
        if not extra or not any(reason in str(error) for reason in ('no_change', 'no_protection_uses')):
            raise
        return {'invalidActionPlan': str(error), 'plan': extra[0]}


def save_evidence(path, evidence):
    def compact(result):
        return {**{k: v for k, v in result.items() if k not in ('curve', 'actions')},
                'actions': [{k: a[k] for k in ('action', 'x', 'y', 'withProtection') if k in a} for a in result['actions']]}
    payload = {**evidence, 'results': [compact(r) for r in evidence['results']]}
    if 'search' in evidence:
        payload['search'] = {**evidence['search'], 'results': [compact(r) for r in evidence['search']['results']]}
    # Best plan retains full summaries and RNG metadata. Other trials retain replayable actions.
    payload['evidenceFormat'] = 'best-full-history; other-trials-summary-and-replayable-actions'
    path.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding='utf-8')
    best = evidence['bestDefault']
    lines = [f'-- 自动生成：{path.relative_to(ROOT).as_posix()} 的 bestDefault。区域坐标为左上角。',
             'return {', f"    seed = {best['seed']}, peak = {best['peak']!r}, finalShare = {best['final']['prosperousShare']!r},",
             f"    population = {best['final']['population']!r}, generation = {best['generation']}, round = {best['round']}, won = {str(best['won']).lower()},", '    actions = {']
    lines += ['        { action = "%s", x = %d, y = %d, withProtection = %s },' % (a['action'], a['x'], a['y'], str(a.get('withProtection', False)).lower()) for a in best['actions']]
    lines += ['    },', '}']
    (ROOT/'scripts/OriginWinabilityPlan.lua').write_text('\n'.join(lines)+'\n', encoding='utf-8')


def refine(args):
    path = ROOT / args.output
    evidence = json.loads(path.read_text(encoding='utf-8'))
    rng = random.Random(20261004)
    candidates = [r for r in evidence['results'] if r['seed'] == 20261002 and r['policy'] != 'baseline']
    candidates.sort(key=lambda r: (r['bestFive'], r['peak']), reverse=True)
    best = candidates[0]
    trials, rejected = [], []
    names = ['craft', 'agriculture', 'foodUp', 'foodDown', 'institution']
    with concurrent.futures.ProcessPoolExecutor(max_workers=args.workers) as pool:
        for start in range(0, args.refine, 8):
            jobs = []
            for i in range(min(8, args.refine-start)):
                parent = best if rng.random() < 0.75 else rng.choice(candidates[:6])
                plan = [{k: a[k] for k in ['action', 'x', 'y']} for a in parent['actions']]
                for _ in range(rng.randint(1, 3)):
                    index = rng.randrange(len(plan))
                    if rng.random() < 0.5:
                        plan[index]['action'] = rng.choice(names)
                    else:
                        plan[index]['x'] = max(1, min(evidence['config']['width'] - evidence['config']['regionSize'] + 1, plan[index]['x'] + rng.randint(-4, 4)))
                        plan[index]['y'] = max(1, min(evidence['config']['height'] - evidence['config']['regionSize'] + 1, plan[index]['y'] + rng.randint(-4, 4)))
                jobs.append((20261002, 'search', start+i, plan))
            for result in pool.map(run_job, jobs):
                if 'invalidActionPlan' in result:
                    rejected.append(result)
                    continue
                trials.append(result)
                candidates.append(result)
                candidates.sort(key=lambda r: (r['bestFive'], r['peak']), reverse=True)
                best = candidates[0]
            if (start+8) % 32 == 0:
                print(f"Search {start+8}/{args.refine}, peak={best['peak']:.3%}, five={best['bestFive']:.3%}", flush=True)
    lua = runtime()
    # Compact prior trial records can omit curves; regenerate the chosen plan through the original model.
    best = plain(lua.execute("return require('OriginWinability').Run(...)", best['seed'], best['policy'],
                            best['choiceSeed'], lua.table_from(best['actions'], recursive=True)))
    best['verifiedFullReplay'] = lua.execute("return require('OriginWinability').Verify(...)", lua.table_from(best, recursive=True))
    plan = lua.table_from(best['actions'], recursive=True)
    evidence['search'] = dict(attempts=args.refine, invalid=len(rejected), rejected=rejected, results=trials, randomSeed=20261004)
    evidence['bestDefault'] = best
    evidence['diagnostics'] = dict(
        bestPlan=plain(lua.execute("return require('OriginWinability').Diagnose(...)", 20261002, plan, False)),
        allExploreNoActions=plain(lua.execute("return require('OriginWinability').Diagnose(...)", 20261002, None, True)))
    save_evidence(path, evidence)
    print(json.dumps(dict(validSearches=len(trials), invalid=len(rejected), wins=sum(r['won'] for r in trials),
                         peak=best['peak'], bestFive=best['bestFive'], replay=best['verifiedFullReplay'])), flush=True)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--seeds', type=int, default=10)
    parser.add_argument('--random', type=int, default=100)
    parser.add_argument('--workers', type=int, default=4)
    parser.add_argument('--output', default='.tmp/verification/winability/playability-v11-results.json')
    parser.add_argument('--policies', nargs='+', help='Limit to named policies; baseline is always included')
    parser.add_argument('--refine', type=int, default=0, help='Refine an existing result with legal action mutations')
    args = parser.parse_args()
    if args.refine:
        refine(args)
        return
    started = time.monotonic()
    lua = runtime()
    tests = plain(lua.execute("return require('OriginTests').Run()"))
    assert tests['ok'], tests
    policies = args.policies or plain(lua.execute("return require('OriginWinability').policies"))
    seeds = [20261002] + [1 + i * 104729 for i in range(args.seeds - 1)]
    jobs = [(seed, policy, 17) for seed in seeds for policy in ['baseline'] + policies]
    jobs += [(20261002, 'random', 1000 + i * 7919) for i in range(args.random)]
    results = []
    with concurrent.futures.ProcessPoolExecutor(max_workers=args.workers) as pool:
        for result in pool.map(run_job, jobs):
            results.append(result)
            if len(results) % 10 == 0:
                print(f"Completed {len(results)}/{len(jobs)}, best peak={max(r['peak'] for r in results):.4%}", flush=True)
    formal = [r for r in results if r['policy'] != 'baseline']
    for result in formal:
        if result['won']:
            result['verifiedFullReplay'] = lua.execute("return require('OriginWinability').Verify(...)", lua.table_from(result, recursive=True))
    best = max((r for r in formal if r['seed'] == 20261002), key=lambda r: (r['bestFive'], r['peak']))
    best['verifiedFullReplay'] = lua.execute("return require('OriginWinability').Verify(...)", lua.table_from(best, recursive=True))
    evidence = dict(date='2026-10-04', luaVersion=lua.eval('_VERSION'), tests=tests,
        seeds=seeds, results=results, bestDefault=best, config=plain(lua.execute("return require('OriginConfig')")),
        elapsedSeconds=time.monotonic()-started,
        sourceSha256={name: hashlib.sha256((ROOT/'scripts'/name).read_bytes()).hexdigest()
                      for name in ['OriginConfig.lua', 'OriginSimulation.lua', 'main.lua']})
    output = ROOT / args.output
    output.parent.mkdir(parents=True, exist_ok=True)
    save_evidence(output, evidence)
    print(json.dumps(dict(runs=len(results), legalRuns=len(formal), wins=sum(r['won'] for r in formal),
                         bestPolicy=best['policy'], bestPeak=best['peak'], bestFive=best['bestFive'],
                         replay=best['verifiedFullReplay'], seconds=evidence['elapsedSeconds']), ensure_ascii=False), flush=True)


if __name__ == '__main__':
    main()
