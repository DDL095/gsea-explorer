# gsealens-explorer (English overview)

> Stateful, question-driven exploratory analysis framework for GSEA enrichment
> results. Designed for use as a Copilot skill or a standalone LLM-agent role.

See [`../README.md`](../README.md) for the canonical (Chinese) readme. This
file is a short English summary for international visitors and search engines.

## What it does

- Reads GSEA result RDS files from **gsealens**, **clusterProfiler**, **fgsea**,
  or **enrichit**.
- Asks the user for experimental context at decision points (tissue, treatment,
  contrast design, hypothesis) before interpreting.
- Extracts the full significant pathway set (no top-N cap) via a persistent
  R REPL.
- Interprets enrichment direction using a |NES| enrichment direction **|NES|**|NES| enrichment direction framework**:
  NES > 0 → enriched in `left_group`, NES < 0 → enriched in `right_group`. The
  sign encodes direction only, never up/down regulation.
- Classifies cross-contrast direction changes into six modes: `true_flip`,
  `p_suppression`, `p_restoration`, `rtp_only`, `rt_only`, `no_flip`.
- Runs G1/G2/G3 quality gates on the synthesis draft before finalizing.
- Emits a dual-format audit log (`audit.log` + `audit.jsonl`) for every run.

## Quick start

```bash
git clone https://github.com/DDL095/gsealens-explorer.git
bash gsealens-explorer/deploy/deploy_to_copilot.sh
```

Then invoke the `gsealens-explorer` skill from Copilot Chat and point it at your
GSEA RDS file.

## Status

v0.5.5 — beta. The gsealens profile is fully validated; clusterProfiler /
fgsea / enrichit profiles are skeletons and become first-class in v0.6.

See [`../CHANGELOG.md`](../CHANGELOG.md) and [`roadmap.md`](roadmap.md).

## License

MIT — see [`../LICENSE`](../LICENSE).
