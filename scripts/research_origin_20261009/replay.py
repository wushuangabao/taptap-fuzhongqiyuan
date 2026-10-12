"""Replay retained study files against their hashed production source snapshots."""
import argparse
import hashlib
import json
from pathlib import Path
import sys
sys.dont_write_bytecode=True
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from research_origin_20261009 import frozen_runtime, plain, ROOT

p=argparse.ArgumentParser()
p.add_argument('results',nargs='+',type=Path)
p.add_argument('--output',type=Path)
args=p.parse_args()
if args.output and args.output.exists(): raise FileExistsError(args.output)
checks=[]
for path in args.results:
    result=json.loads(path.read_text(encoding='utf-8'))
    manifest=json.loads((path.parent/'manifest.json').read_text(encoding='utf-8'))
    for name,expected in manifest['sourceSha256'].items():
        actual=hashlib.sha256((path.parent/'source'/name).read_bytes()).hexdigest()
        assert actual==expected,name
    lua=frozen_runtime(path.parent/'source')
    check=plain(lua.execute('''
        local r=...
        local S=require('OriginSimulation')
        local function equal(a,b)
            if type(a)~=type(b) then return false end
            if type(a)~='table' then return a==b end
            for k,v in pairs(a) do if not equal(v,b[k]) then return false end end
            for k in pairs(b) do if a[k]==nil then return false end end
            return true
        end
        local w=S.Replay(r.seed,r.actions)
        local ok,reason=S.VerifyReplay(w); assert(ok,reason)
        assert(#w.history==#r.curve,'history length')
        for i,report in ipairs(w.history) do assert(equal(report.summary,r.curve[i]),'summary '..i) end
        assert(equal(w.cells,r.finalCells),'saved final cells')
        assert(equal(w.rng,r.finalRng),'saved rng')
        assert(equal(w.actions,r.actions),'saved actions')
        assert(w.won==r.won and w.generation==r.generation,'ending')
        return {seed=w.seed,policy=r.policy,won=w.won,generation=w.generation,
            actions=#w.actions,generations=#w.history-1,fullReplay=true,savedEvidenceMatched=true}
    ''',lua.table_from(result,recursive=True)))
    checks.append(check)
    print(json.dumps(check,ensure_ascii=False),flush=True)
if args.output:
    args.output.write_text(json.dumps(checks,ensure_ascii=False,indent=2),encoding='utf-8')
