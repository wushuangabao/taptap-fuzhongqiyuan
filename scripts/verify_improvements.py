"""Read-only Lua 5.4 checks for probabilistic improvements; no build/submit."""
import hashlib
import json
from pathlib import Path
import sys
import subprocess
sys.dont_write_bytecode = True
from verify_winability import runtime, plain

ROOT = Path(__file__).resolve().parents[1]
SUITES = ['OriginImprovementTests', 'OriginTests', 'OriginLocalMilestonesTests',
          'OriginLocalMilestonesViewTests', 'OriginGridIntegrationTests',
          'OriginTerrainIntegrationTests', 'OriginRegionIntegrationTests',
          'OriginSettingsTests', 'OriginSettingsViewTests']
SOURCES = ['OriginConfig', 'OriginSimulation', 'OriginRecommendation', 'OriginWinability',
           'OriginView', 'OriginWidgets', 'OriginTips', 'OriginSettings', 'OriginSettingsView', 'OriginLocalMilestones', 'main'] + SUITES


def main():
    output = ROOT/'.tmp/verification/settings/checks.json'
    subprocess.run(['git', 'check-ignore', '--quiet', str(output)], cwd=ROOT, check=True)
    output.parent.mkdir(parents=True, exist_ok=True)
    def hashes():
        return {name: hashlib.sha256((ROOT/'scripts'/f'{name}.lua').read_bytes()).hexdigest()
                for name in SOURCES}
    before = hashes()
    results = {}
    for name in SUITES:
        lua = runtime()
        lua.execute('print = function() end')
        results[name] = plain(lua.execute('return require(...).Run()', name))
        print(json.dumps({'suite': name, 'passed': results[name]['passed'], 'failed': results[name]['failed'],
                          'failures': [item for item in results[name]['results'] if not item['passed']]},
                         ensure_ascii=False), flush=True)
    evidence = {'modelVersion': plain(lua.execute('return require("OriginConfig").modelVersion')), 'luaVersion': lua.eval('_VERSION'),
                'suites': results, 'sourceSha256': before, 'sourcesUnchanged': before == hashes(),
                'scope': 'Model and UI callback contracts; engine screenshots verified separately'}
    output.write_text(json.dumps(evidence, ensure_ascii=False, indent=2), encoding='utf-8')
    assert evidence['sourcesUnchanged'], 'Sources changed during checks'
    assert all(item['ok'] for item in results.values()), 'Tests failed; see evidence'


if __name__ == '__main__':
    main()
