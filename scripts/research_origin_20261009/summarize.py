"""Create auditable aggregate tables from completed study records, without rerunning rules."""
import collections
import json
import math
from pathlib import Path
import statistics

ROOT=Path(__file__).resolve().parents[2]
BASE=ROOT/'.tmp/verification/research-origin-20261009'
BATCH=BASE/'multi-seed'
summaries=json.loads((BATCH/'summary.json').read_text(encoding='utf-8'))
manifest=json.loads((BATCH/'manifest.json').read_text(encoding='utf-8'))
records={(r['seed'],r['policy']):json.loads((BATCH/f"{r['seed']}-{r['policy']}.json").read_text(encoding='utf-8')) for r in summaries}
assert len(records)==len(manifest['seeds'])*len(manifest['policies'])
assert all(r['verifiedFullReplay'] for r in summaries)
labels={
 'baseline':'全程跳过', 'craft_center':'中心格 只做工艺','rec_center':'中心格 现有推荐',
 'craft_scan':'逐行换格 只做工艺','rec_scan':'逐行换格 现有推荐',
 'craft_hubs':'四象限强格 只做工艺','rec_hubs':'四象限强格 现有推荐',
 'institution_strong':'强格持续制度培养','balanced':'前30轮制度 后补短板',
 'balanced_protect':'均衡 前3轮附保护','network':'分散制度 后补短板',
 'network_risk':'分散制度 危险时保护','network_skip':'分散制度 30轮后跳过',
 'core102':'中心格 食物低于1.02补农业'}
aggregate={}
for policy in manifest['policies']:
    rows=[r for r in summaries if r['policy']==policy]
    gens=[r['generation'] for r in rows if r['won']]
    aggregate[policy]={
        'label':labels[policy], 'wins':len(gens),'runs':len(rows),
        'winningGenerations':gens,'medianWinningGeneration':statistics.median(gens) if gens else None,
        'minPeak':min(r['peak'] for r in rows),'maxPeak':max(r['peak'] for r in rows),
        'medianPeak':statistics.median(r['peak'] for r in rows),
        'minBestFive':min(r['bestFive'] for r in rows),'maxBestFive':max(r['bestFive'] for r in rows),
        'failedSeeds':[r['seed'] for r in rows if not r['won']],
        'actionCounts':dict(collections.Counter(a['action'] for r in rows for a in records[r['seed'],policy]['actions'])),
    }
pairs={}
for selector in ['center','scan','hubs']:
    rows=[]
    for seed in manifest['seeds']:
        a,b=records[seed,'craft_'+selector],records[seed,'rec_'+selector]
        coordinates=all((x['x'],x['y'])==(y['x'],y['y']) for x,y in zip(a['actions'],b['actions']))
        assert coordinates
        rows.append({'seed':seed,'sameCoordinatesOnCommonTurns':coordinates,'sameActions':a['actions']==b['actions'],
          'sameCurve':a['curve']==b['curve'],'craftWon':a['won'],'recommendationWon':b['won'],
          'craftGeneration':a['generation'],'recommendationGeneration':b['generation']})
    pairs[selector]=rows
rounding=[]
for seed in manifest['seeds']:
    for turn,d in enumerate(records[seed,'core102']['decisions'],1):
        v=d['metric']['foodRatio']
        if (v<1.02)!=(float(f'{v:.3f}')<1.02): rounding.append({'seed':seed,'turn':turn,'value':v})
opening={str(seed):json.loads((BATCH/f'opening-{seed}.json').read_text(encoding='utf-8'))['counts'] for seed in manifest['seeds']}
analysis={'runs':len(summaries),'seeds':manifest['seeds'],'aggregate':aggregate,'pairedSelectionControls':pairs,
 'openingRecommendations':opening,'displayRoundingMismatchesForCore102':rounding,
 'institutionCrossoverGenerations':math.log(1.15)/math.log(1.015/1.002),
 'institutionRelativeCraftAfter10':(1.015/1.002)**10,
 'productionUnchanged':manifest['productionUnchanged'],'designUnchanged':manifest['designUnchanged'],
 'maxMigrationConservationError':max(r['maxMigrationError'] for r in records.values())}
out=BASE/'analysis.json'
assert not out.exists()
out.write_text(json.dumps(analysis,ensure_ascii=False,indent=2),encoding='utf-8')
lines=['# 富种起源逐局实验记录','',
 '所有对局使用 origin-1.8.0 正式默认规则，获胜即停止；失败局运行到250世代。全部通过正式完整重放。',
 '五代最低值指所有连续五世代窗口中最好的窗口下限；不把单代峰值视为获胜。','']
for seed in manifest['seeds']:
    lines += [f'## 种子 {seed}','','| 策略 | 胜负 | 首胜世代 | 繁荣峰值 | 峰值世代 | 最佳五代最低值 | 最长达标连续世代 | 证据 |','|---|---|---:|---:|---:|---:|---:|---|']
    for policy in manifest['policies']:
        r=records[seed,policy]
        lines.append(f"| {labels[policy]} | {'胜' if r['won'] else '负'} | {r['generation'] if r['won'] else '—'} | {r['peak']:.4%} | {r['peakGeneration']} | {r['bestFive']:.4%} | {r['maxStreak']} | [完整记录](multi-seed/{seed}-{policy}.json) |")
    lines += ['']
(BASE/'results.md').write_text('\n'.join(lines),encoding='utf-8')
print(json.dumps(analysis,ensure_ascii=False,indent=2))
