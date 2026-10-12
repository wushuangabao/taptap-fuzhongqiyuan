"""Read-only Lua 5.4 verification. No Maker build, push or preview launch.

py -3.11 scripts/verify_local_milestones.py
Uses the same existing lupa 2.8 runtime as verify_winability.py.
"""
import argparse
import hashlib
import json
from pathlib import Path
import sys
sys.dont_write_bytecode = True
from verify_winability import runtime, plain

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--suite', choices=['all', 'model', 'view'], default='all')
    args = parser.parse_args()
    sources = ['OriginConfig.lua', 'OriginSimulation.lua', 'OriginProgress.lua', 'OriginView.lua', 'OriginTests.lua',
               'main.lua', 'OriginLocalMilestones.lua', 'OriginLocalMilestonesTests.lua',
               'OriginLocalMilestonesAcceptance.lua', 'OriginLocalMilestonesViewTests.lua', 'verify_local_milestones.py']
    sources += [name for name in ['OriginRegions.lua', 'OriginRegionLayout.lua', 'OriginTerrain.lua']
                if (ROOT/'scripts'/name).exists()]
    def hashes():
        return {name: hashlib.sha256((ROOT/'scripts'/name).read_bytes()).hexdigest() for name in sources}
    before_hashes = hashes()
    lua = runtime()
    suites = ['OriginTests', 'OriginLocalMilestonesTests'] if args.suite != 'view' else []
    results = {name: plain(lua.execute("return require(...).Run()", name)) for name in suites}
    # UI substitutes must be isolated from the model runtime and never shipped into real UI state.
    if args.suite != 'model':
        results['OriginLocalMilestonesViewTests'] = plain(runtime().execute(
            "return require('OriginLocalMilestonesViewTests').Run()"))
    for name in sources:
        if name.endswith('.lua'):
            lua.execute('assert(loadfile(...))', str(ROOT / 'scripts' / name))
    after_hashes = hashes()
    changed = [name for name in sources if before_hashes[name] != after_hashes[name]]
    evidence = dict(date='2026-10-08', luaVersion=lua.eval('_VERSION'), tests=results,
                    runtimeVisualAcceptance='UNDETERMINED: local preview stopped; runtime missing',
                    sourceSha256=before_hashes, sourceChangedDuringRun=changed)
    filename = 'local-milestones-results.json' if args.suite == 'all' else f'local-milestones-{args.suite}-results.json'
    out = ROOT / '.tmp/verification/local-milestones' / filename
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(evidence, ensure_ascii=False, indent=2), encoding='utf-8')
    print(json.dumps(dict(passed=sum(r['passed'] for r in results.values()),
                         failed=sum(r['failed'] for r in results.values()), evidence=str(out)), ensure_ascii=False))
    assert all(r['ok'] for r in results.values()), 'Local milestones verification failed; see evidence'
    assert not changed, 'Sources changed during verification; rerun after the edit batch finishes'


if __name__ == '__main__':
    main()
