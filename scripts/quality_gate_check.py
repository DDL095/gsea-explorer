"""
quality_gate_check.py — G1/G2/G3 quality gates (gsealens-explorer v0.2.1)
Checks the synthesis_draft for: data support, anti-patterns, limitations.

Usage:
    python quality_gate_check.py <report.md> <csv_dir>
Exit: 0=pass, 1=fail, 2=file missing
"""

import re
import sys
from pathlib import Path


def gate_g1_data_support(md: str, csv_files: list) -> dict:
    sections = re.split(r'^## ', md, flags=re.MULTILINE)
    exempt = ["方法", "局限", "参考", "文献", "输出文件", "声明",
              "agent 版本", "生成元数据", "一句话", "总结"]
    failures = []
    for sec in sections:
        title = sec.split('\n')[0]
        if any(kw in title for kw in exempt):
            continue
        if not any(csv in sec for csv in csv_files):
            failures.append(f"  - '{title}' 无 CSV 数据引用")
    return {"gate": "G1_data_support",
            "result": "PASS" if not failures else "FAIL",
            "details": failures}


def gate_g2_antipatterns(md: str) -> dict:
    patterns = {
        "inflammaging 模板": [
            r"inflammaging\s*七联征", r"七联征.*齐全",
            r"典型\s*inflammaging", r"典型\s*aging\s*表型",
        ],
        "cancer 模板": [r"经典\s*cancer\s*hallmarks", r"Hanahan\s*Weinberg"],
        "顺序总结": [r"(\w+组有[^,;\n]+[,;]\s*){2,}\w+组有"],
    }
    failures = []
    for cat, pats in patterns.items():
        for p in pats:
            n = len(re.findall(p, md, re.IGNORECASE | re.MULTILINE))
            if n:
                failures.append(f"  - [{cat}] 匹配 {n} 次: '{p}'")
    return {"gate": "G2_antipatterns",
            "result": "PASS" if not failures else "FAIL",
            "details": failures}


def gate_g3_limitations(md: str) -> dict:
    required = {
        "FDR 阈值": r"FDR\s*[<>=]?\s*0\.\d+",
        "NES 阈值": r"(?:\|NES| NES)[^a-zA-Z]*[<>=]?\s*[12]\.\d+",
        "Interaction Term 缺失": r"interaction|互作",
        "Collection 详情未展开": r"GO:BP.*(?:未|未深入)|Reactome.*(?:未|未深入)|KEGG.*(?:未|未深入)",
    }
    failures = []
    for label, pat in required.items():
        if not re.search(pat, md, re.IGNORECASE):
            failures.append(f"  - 缺少 {label}")
    return {"gate": "G3_limitations",
            "result": "PASS" if not failures else "FAIL",
            "details": failures}


def run_all(md: str, csv_files: list) -> dict:
    g1 = gate_g1_data_support(md, csv_files)
    g2 = gate_g2_antipatterns(md)
    g3 = gate_g3_limitations(md)
    overall = "PASS" if all(x["result"] == "PASS" for x in (g1, g2, g3)) else "FAIL"
    return {"overall": overall, "gates": {"G1": g1, "G2": g2, "G3": g3},
            "next": "S8" if overall == "PASS" else "back_to_S6"}


def main():
    if len(sys.argv) < 3:
        print("Usage: python quality_gate_check.py <report.md> <csv_dir>")
        sys.exit(2)

    md_path = Path(sys.argv[1])
    csv_dir = Path(sys.argv[2])

    if not md_path.exists():
        print(f"ERROR: report not found: {md_path}"); sys.exit(2)
    if not csv_dir.exists():
        print(f"ERROR: csv dir not found: {csv_dir}"); sys.exit(2)

    md = md_path.read_text(encoding="utf-8")
    csvs = [f.name for f in csv_dir.glob("*.csv")]
    result = run_all(md, csvs)

    print("=" * 60)
    print(f"质量门控: {result['overall']}")
    print("=" * 60)
    for name, g in result["gates"].items():
        print(f"\n[{name}] {g['gate']}: {g['result']}")
        for d in g["details"]:
            print(d)
    print("\n" + "=" * 60)
    print(f"Next: {result['next']}")
    print("=" * 60)
    sys.exit(0 if result["overall"] == "PASS" else 1)


if __name__ == "__main__":
    main()
