"""
trigger_consistency.py — Verify gsealens-explorer name / description
consistency across all 6 deployment locations.

Each location has a different audience and language, so the must-have keyword
set is location-specific. Universal checks:
  - `name` field must be exactly "gsealens-explorer"
  - description must not contain any legacy name patterns

Run from repo root:
    python tests/trigger_consistency.py
"""
import re
import sys
from pathlib import Path

REPO = Path('d:/BaiduYunDrive/OneDrive/github仓库/gsea-explorer')

LOCATIONS = [
    {
        'label': 'C:prompts/gsealens-explorer.agent.md',
        'path':  Path('c:/Users/Administrator/AppData/Roaming/Code/User/prompts/gsealens-explorer.agent.md'),
        'lang':  'zh-primary',
        'role':  'agent (top-level user-invocable)',
        # Bilingual trigger: must contain all of these so both Chinese and
        # English keyword inputs will load this skill/agent.
        'must_have': [
            '|NES|', 'RDS', 'NES', 'leading edge', 'gsealens',
            'clusterProfiler', 'rds_path', '多组织 crosstalk',
            'GSEA 富集分析', 'NES 解读', '生物主题讨论', 'MSigDB 涌现发现',
            'enrichit', 'fgsea',  # cross-platform reach
        ],
    },
    {
        'label': 'C:skill/SKILL.md',
        'path':  Path('c:/Users/Administrator/.copilot/skills/gsealens-explorer/SKILL.md'),
        'lang':  'zh-primary',
        'role':  'skill (master definition)',
        'must_have': [
            '|NES|', 'RDS', 'NES', 'leading edge', 'gsealens',
            'clusterProfiler', 'rds_path', '多组织 crosstalk',
            'GSEA 富集分析', 'NES 解读', '生物主题讨论', 'MSigDB 涌现发现',
            'enrichit', 'fgsea',
        ],
    },
    {
        'label': 'C:skill/agents/gsealens-explorer.md',
        'path':  Path('c:/Users/Administrator/.copilot/skills/gsealens-explorer/agents/gsealens-explorer.md'),
        'lang':  'en-primary-zh-appended',
        'role':  'agent role (sub-skill invocation)',
        # Bilingual: English body + Chinese trigger tail
        'must_have': [
            'GSEA', 'NES', 'RDS', 'leading edge', 'gsealens',
            'clusterProfiler', 'enrichit', 'fgsea',
            # Chinese tail keywords for Chinese-speaking users
            'GSEA 富集分析', 'NES 解读', '多组织 crosstalk',
            '生物主题讨论', 'MSigDB 涌现发现', 'rds_path',
        ],
    },
    {
        'label': 'D:SKILL.md',
        'path':  REPO / 'SKILL.md',
        'lang':  'zh-primary',
        'role':  'skill (master definition, public repo source)',
        'must_have': [
            '|NES|', 'RDS', 'NES', 'leading edge', 'gsealens',
            'clusterProfiler', 'rds_path', '多组织 crosstalk',
            'GSEA 富集分析', 'NES 解读', '生物主题讨论', 'MSigDB 涌现发现',
            'enrichit', 'fgsea',
        ],
    },
    {
        'label': 'D:agents/gsealens-explorer.md',
        'path':  REPO / 'agents/gsealens-explorer.md',
        'lang':  'en-primary-zh-appended',
        'role':  'agent role (sub-skill invocation, public repo source)',
        'must_have': [
            'GSEA', 'NES', 'RDS', 'leading edge', 'gsealens',
            'clusterProfiler', 'enrichit', 'fgsea',
            # Chinese tail keywords
            'GSEA 富集分析', 'NES 解读', '多组织 crosstalk',
            '生物主题讨论', 'MSigDB 涌现发现', 'rds_path',
        ],
    },
    {
        'label': 'D:gsealens-explorer.agent.md',
        'path':  REPO / 'gsealens-explorer.agent.md',
        'lang':  'zh-primary',
        'role':  'agent (top-level user-invocable, public repo source)',
        'must_have': [
            '|NES|', 'RDS', 'NES', 'leading edge', 'gsealens',
            'clusterProfiler', 'rds_path', '多组织 crosstalk',
            'GSEA 富集分析', 'NES 解读', '生物主题讨论', 'MSigDB 涌现发现',
            'enrichit', 'fgsea',
        ],
    },
]

# Legacy names that must NEVER appear in any description. Permitted only
# in CHANGELOG.md and test fixtures.
MUST_NOT_HAVE = ['gsea-explorer', 'GSEA Explorer', 'GSEAlens-style',
                 'GSEAlens 风格', 'GSEAlens |NES|']


def extract_frontmatter_field(text, field):
    if not text.startswith('---'):
        return ''
    end = text.find('\n---', 3)
    if end == -1:
        return ''
    block = text[3:end]
    m = re.search(rf'^{field}:\s*["\']?(.*?)["\']?\s*$', block, re.MULTILINE | re.DOTALL)
    return m.group(1) if m else ''


def main():
    print('Description trigger keyword consistency check')
    print('=' * 70)
    overall_ok = True
    failures = []

    for loc in LOCATIONS:
        label = loc['label']
        path = loc['path']
        print(f'\n[{label}]')
        print(f'  role: {loc["role"]}  |  lang: {loc["lang"]}')

        if not path.exists():
            print('  STATUS: FILE MISSING')
            failures.append((label, 'missing'))
            overall_ok = False
            continue

        text = path.read_text(encoding='utf-8')
        name = extract_frontmatter_field(text, 'name')
        desc = extract_frontmatter_field(text, 'description')

        name_ok = name == 'gsealens-explorer'
        print(f'  [name]  {"OK" if name_ok else "FAIL"}  {name!r}')
        if not name_ok:
            failures.append((label, f'name={name!r}'))
            overall_ok = False

        loc_ok = name_ok
        for kw in loc['must_have']:
            hit = kw in desc
            mark = 'OK  ' if hit else 'FAIL'
            print(f'  [must]  {mark}  {kw!r}')
            if not hit:
                loc_ok = False
                failures.append((label, f'missing {kw!r} in description'))
                overall_ok = False

        for kw in MUST_NOT_HAVE:
            hit = kw in desc
            mark = 'OK  ' if not hit else 'FAIL'
            print(f'  [no-go] {mark}  {kw!r}')
            if hit:
                loc_ok = False
                failures.append((label, f'legacy {kw!r} in description'))
                overall_ok = False

        print(f'  status: {"PASS" if loc_ok else "FAIL"}')

    print()
    print('=' * 70)
    if overall_ok:
        print('ALL PASS')
        print('  - LLM will load the gsealens-explorer skill / agent on')
        print('    any of the must-have keywords in any location')
        print('  - All name fields are exactly "gsealens-explorer"')
        print('  - No legacy names in any description (where LLM looks for triggers)')
        return 0
    print('FAIL')
    print('Issues:')
    for label, reason in failures:
        print(f'  - {label}: {reason}')
    return 1


if __name__ == '__main__':
    sys.exit(main())
