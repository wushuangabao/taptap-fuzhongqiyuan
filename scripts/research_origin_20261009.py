"""Isolated formal-model study. Never invokes verify_winability.main/save_evidence.

Creates a new evidence directory per batch; refuses to overwrite an existing batch.
Only verify_winability.runtime/plain are reused. No production config overrides.
"""
import argparse
import concurrent.futures
from datetime import datetime
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import sys
import time
sys.dont_write_bytecode = True
from verify_winability import runtime, plain, ROOT

FORMAL = ['OriginConfig.lua', 'OriginSimulation.lua', 'OriginProgress.lua',
          'OriginRecommendation.lua', 'OriginWinability.lua', 'OriginLocalMilestones.lua',
          'OriginView.lua', 'main.lua', 'OriginRegions.lua', 'OriginTerrain.lua',
          'OriginWidgets.lua', 'OriginCellVisuals.lua', 'OriginWinabilityPlan.lua']

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def dump(path, value):
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2), encoding='utf-8')

def frozen_runtime(source):
    lua = runtime()
    lua.globals().frozen_source = str(source).replace('\\', '/')
    lua.execute("package.path=frozen_source..'/?.lua;'..package.path")
    return lua

def job(args):
    source, seed, policy, verify = args
    start=time.monotonic()
    lua=frozen_runtime(source)
    result=plain(lua.execute("return require('Experiment').Run(...)",seed,policy,verify))
    result['elapsedSeconds']=time.monotonic()-start
    return result

def main():
    p=argparse.ArgumentParser()
    p.add_argument('--batch', required=True)
    p.add_argument('--seeds',type=int,nargs='+',default=[20261002,1,104730,209459,314188])
    p.add_argument('--policies',nargs='+',required=True)
    p.add_argument('--workers',type=int,default=2)
    p.add_argument('--verify',action='store_true')
    args=p.parse_args()
    if not args.batch or args.batch in ('.', '..') or '/' in args.batch or '\\' in args.batch or ':' in args.batch:
        p.error('--batch must be a new directory name, not a path')
    output=ROOT/'.tmp/verification/research-origin-20261009'/args.batch
    subprocess.run(['git', 'check-ignore', '--quiet', str(output)], cwd=ROOT, check=True)
    output.mkdir(parents=True,exist_ok=False)
    source=output/'source'; source.mkdir()
    for name in FORMAL: shutil.copyfile(ROOT/'scripts'/name,source/name)
    shutil.copyfile(ROOT/'scripts/research_origin_20261009/Experiment.lua',source/'Experiment.lua')
    shutil.copyfile(Path(__file__),source/'research_origin_20261009.py')
    shutil.copyfile(ROOT/'scripts/verify_winability.py',source/'verify_winability.py')
    shutil.copyfile(ROOT/'docs/game-design.md',source/'game-design.md')
    manifest={
        'startedAt':datetime.now().astimezone().isoformat(),
        'scope':'Official Lua 5.4 model, default config, no engine/device verification',
        'seeds':args.seeds,'policies':args.policies,'verifyFullReplay':args.verify,
        'sourceSha256':{f.name:sha(f) for f in source.iterdir()},
        'gitHead':subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT,text=True).strip(),
        'command':sys.argv,
    }
    lua=frozen_runtime(source)
    manifest['config']=plain(lua.execute("local c=require('OriginConfig'); return c"))
    manifest['luaVersion']=lua.eval('_VERSION')
    for seed in args.seeds:
        dump(output/f'opening-{seed}.json',plain(lua.execute("return require('Experiment').Opening(...)",seed)))
    dump(output/'manifest.json',manifest)
    start=time.monotonic(); summaries=[]
    jobs=[(source,seed,policy,args.verify) for seed in args.seeds for policy in args.policies]
    with concurrent.futures.ProcessPoolExecutor(max_workers=args.workers) as pool:
        for r in pool.map(job,jobs):
            dump(output/f"{r['seed']}-{r['policy']}.json",r)
            summary={k:r[k] for k in ['seed','policy','won','generation','round','peak','peakGeneration',
                'bestFive','maxStreak','firstWinGeneration','verifiedFullReplay','elapsedSeconds']}
            summary['final']=r['final']; summaries.append(summary)
            print(json.dumps(summary,ensure_ascii=False),flush=True)
    manifest['elapsedSeconds']=time.monotonic()-start
    manifest['finishedAt']=datetime.now().astimezone().isoformat()
    manifest['productionUnchanged']={name:sha(ROOT/'scripts'/name)==manifest['sourceSha256'][name] for name in FORMAL}
    manifest['designUnchanged']=sha(ROOT/'docs/game-design.md')==manifest['sourceSha256']['game-design.md']
    dump(output/'manifest.json',manifest); dump(output/'summary.json',summaries)
    assert all(manifest['productionUnchanged'].values()) and manifest['designUnchanged'], 'Production source changed during batch'
    print(f'Completed {len(summaries)} runs in {manifest["elapsedSeconds"]:.1f}s: {output}',flush=True)

if __name__=='__main__': main()
