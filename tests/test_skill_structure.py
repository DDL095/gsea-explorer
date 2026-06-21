"""
test_skill_structure.py — Structural smoke test for the gsealens-explorer repo.

Runs without R / Python deps beyond the stdlib. Verifies:
  1. SKILL.md and gsealens-explorer.agent.md have valid YAML frontmatter with the
     required fields.
  2. Every file referenced by scripts/ exists (no broken cross-references).
  3. Every profile YAML declares platform, status, and result_fields.
  4. No committed file contains obvious personal-data leakage (Windows drive
     paths, known study identifiers).
  5. version metadata in SKILL.md matches CHANGELOG.md latest version.

Run from the repo root:
    python tests/test_skill_structure.py
Exit: 0 = all pass, 1 = at least one fail.
"""

import re
import sys
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parent.parent

# Project name (must stay in sync with frontmatter name / repo URL / CITATION.cff).
PROJECT_NAME = "gsealens-explorer"

# Patterns that indicate personal-data leakage and should never be committed.
LEAKAGE_PATTERNS = [
    # Absolute Windows paths starting with a drive letter
    re.compile(r'[A-Za-z]:\\\\', re.IGNORECASE),
    re.compile(r'[A-Za-z]:/(?=Users|BaiduYunDrive|Program Files)', re.IGNORECASE),
    # Known study-name patterns used in private examples
    re.compile(r'ZYH_衰老|HSG_肺肿瘤|XSH_达乌尔黄鼠', re.IGNORECASE),
    # Lab usernames
    re.compile(r'\b(?:sealgod|Administrator)\b', re.IGNORECASE),
    # Legacy project name (must stay renamed — broad disclaimer for Broad's tool)
    re.compile(r'\bgsea-explorer\b(?!-)', re.IGNORECASE),
    re.compile(r'\bGSEA Explorer\b(?!-)', re.IGNORECASE),
]

REQUIRED_FRONTMATTER_SKILL = {"name", "description", "metadata"}
REQUIRED_FRONTMATTER_AGENT = {"description", "name"}
REQUIRED_METADATA_KEYS = {"version", "last_updated", "status", "task_type"}
REQUIRED_PROFILE_KEYS = {"platform", "status", "result_fields"}


def parse_frontmatter(text):
    if not text.startswith('---'):
        return None, None
    end = text.find('\n---', 3)
    if end == -1:
        return None, None
    raw = text[3:end].strip()
    # Tiny YAML subset parser: top-level key: value (no nesting required for our check)
    fm = {}
    for line in raw.splitlines():
        m = re.match(r'^([A-Za-z_][\w-]*)\s*:\s*(.*)$', line)
        if m and m.group(1) not in fm:
            fm[m.group(1)] = m.group(2).strip().strip('"').strip("'")
    return fm, text[end:]


def fail(msg):
    print(f"  FAIL: {msg}")
    return False


def check_frontmatter():
    print("[1] SKILL.md / agent.md frontmatter")
    ok = True
    skill_path = REPO_ROOT / 'SKILL.md'
    agent_path = REPO_ROOT / 'gsealens-explorer.agent.md'
    for path, required, required_meta in [
        (skill_path, REQUIRED_FRONTMATTER_SKILL, REQUIRED_METADATA_KEYS),
        (agent_path, REQUIRED_FRONTMATTER_AGENT, None),
    ]:
        if not path.exists():
            ok = fail(f"{path.name} missing") and ok
            continue
        text = path.read_text(encoding='utf-8')
        fm, _ = parse_frontmatter(text)
        if not fm:
            ok = fail(f"{path.name} has no frontmatter") and ok
            continue
        missing = required - set(fm.keys())
        if missing:
            ok = fail(f"{path.name} frontmatter missing: {missing}") and ok
        if required_meta and 'metadata' in fm:
            # metadata block must contain version / last_updated / status / task_type
            meta_block = text.split('metadata:', 1)[1].split('\n\n', 1)[0]
            for key in required_meta:
                if key not in meta_block:
                    ok = fail(f"{path.name} metadata missing key: {key}") and ok
        print(f"  {path.name}: name={fm.get('name')!r}")
    return ok


def check_profiles():
    print("[2] profiles/*.yaml completeness")
    ok = True
    profiles_dir = REPO_ROOT / 'profiles'
    if not profiles_dir.exists():
        return fail("profiles/ directory missing")
    yamls = list(profiles_dir.glob('*.yaml'))
    if not yamls:
        return fail("no profile YAMLs found")
    for yf in yamls:
        text = yf.read_text(encoding='utf-8')
        for key in REQUIRED_PROFILE_KEYS:
            if key not in text:
                ok = fail(f"{yf.name} missing key: {key}") and ok
        # status value sanity
        m = re.search(r'^status:\s*(\w+)', text, re.MULTILINE)
        if m and m.group(1) not in {'full', 'skeleton', 'planned'}:
            ok = fail(f"{yf.name} has unexpected status: {m.group(1)}") and ok
        print(f"  {yf.name}: ok")
    return ok


def check_scripts_exist():
    print("[3] scripts/ referenced files exist")
    ok = True
    scripts_dir = REPO_ROOT / 'scripts'
    expected = [
        'sniff_platform.R',
        'extract_gsea_capsule.R',
        'audit_logger.py',
        'quality_gate_check.py',
        'run_full_pipeline.ps1',
        'run_full_pipeline.sh',
    ]
    for name in expected:
        if not (scripts_dir / name).exists():
            ok = fail(f"scripts/{name} missing") and ok
        else:
            print(f"  scripts/{name}: ok")
    return ok


def check_no_leakage():
    print("[4] no personal data leakage in committed files")
    ok = True
    # Scan tracked-ish files (skip .git, tests/testdata, etc.)
    skip_dirs = {'.git', 'node_modules', 'out', '.audit', 'tests'}
    # Some files legitimately contain the legacy names as part of historical
    # records (CHANGELOG), test fixtures, or the regex source itself.
    whitelisted_paths = {'CHANGELOG.md'}
    for path in REPO_ROOT.rglob('*'):
        if not path.is_file():
            continue
        rel = path.relative_to(REPO_ROOT).as_posix()
        if any(rel.startswith(d + '/') or rel == d for d in skip_dirs):
            continue
        if rel.endswith(('.png', '.jpg', '.jpeg', '.gif', '.webp', '.ipynb')):
            continue
        if rel in whitelisted_paths:
            continue
        try:
            text = path.read_text(encoding='utf-8', errors='ignore')
        except Exception:
            continue
        for pat in LEAKAGE_PATTERNS:
            for m in pat.finditer(text):
                # Allow the .gitignore entry that contains the pattern itself
                if path.name == '.gitignore' and 'local_overrides' in text:
                    continue
                ok = fail(f"{rel}: leakage pattern {pat.pattern!r} matched") and ok
                break
    if ok:
        print("  no leakage patterns found")
    return ok


def check_version_alignment():
    print("[5] SKILL.md version matches CHANGELOG latest")
    skill_text = (REPO_ROOT / 'SKILL.md').read_text(encoding='utf-8')
    m_skill = re.search(r'version:\s*"([\d.]+)"', skill_text)
    if not m_skill:
        return fail("SKILL.md metadata.version not found")
    skill_ver = m_skill.group(1)

    changelog_text = (REPO_ROOT / 'CHANGELOG.md').read_text(encoding='utf-8')
    m_cl = re.search(r'^##\s*\[([\d.]+)\]', changelog_text, re.MULTILINE)
    if not m_cl:
        return fail("CHANGELOG.md has no version section")
    cl_ver = m_cl.group(1)

    if skill_ver != cl_ver:
        return fail(f"version mismatch: SKILL.md={skill_ver} CHANGELOG={cl_ver}")
    print(f"  both at v{skill_ver}")
    return True


def main():
    print(f"repo root: {REPO_ROOT}")
    print()
    checks = [
        check_frontmatter,
        check_profiles,
        check_scripts_exist,
        check_no_leakage,
        check_version_alignment,
    ]
    all_ok = True
    for chk in checks:
        all_ok = chk() and all_ok
        print()
    print("=" * 50)
    if all_ok:
        print("ALL PASS")
        sys.exit(0)
    else:
        print("FAIL")
        sys.exit(1)


if __name__ == '__main__':
    main()
