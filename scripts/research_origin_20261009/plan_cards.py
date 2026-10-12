"""Export exact default-seed action cards from saved formal-model evidence."""
import json
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
BASE=ROOT/'.tmp/verification/research-origin-20261009'
names={'agriculture':'农艺改良','craft':'工艺改良','institution':'制度试验','foodUp':'更多务农','foodDown':'更多制物','skip':'跳过本轮'}
policies=[('core102','中心格手动兼顾农工'),('rec_center','中心格按现有推荐'),('network','分散探索制度再补短板')]
lines=['# 富种起源默认地图逐轮操作表','','适用种子20261002和本报告源码快照的 origin-1.8.0。必须从新局开始，坐标先横后纵，从1计数。三条路线分别从头执行，不能混拼。都不使用附加保护；一轮确认一次，等演进结束再执行下一项。','']
for policy,title in policies:
    r=json.loads((BASE/'multi-seed'/f'20261002-{policy}.json').read_text(encoding='utf-8'))
    lines += [f'## {title}','',f"第{r['round']}轮、第{r['generation']}世代获胜。繁荣峰值{r['peak']:.4%}，最佳五代窗口最低{r['bestFive']:.4%}。",'',
        '| 轮次 | 操作前世代 | 地块 | 行动 | 附加保护 |','|---:|---:|---|---|---|']
    for a in r['actions']:
        lines.append(f"| {a['round']} | {a['generation']} | ({a['x']}, {a['y']}) | {names[a['action']]} | {'是' if a['withProtection'] else '否'} |")
    lines += ['',f"[完整行动与逐代数据](multi-seed/20261002-{policy}.json)",'']
out=BASE/'default-actions.md'
assert not out.exists()
out.write_text('\n'.join(lines),encoding='utf-8')
print(out)
