#!/usr/bin/env bash
# run_full_pipeline.sh — One-shot S0→S8 driver (gsealens-explorer v0.2.1)
#
# Usage:
#   bash run_full_pipeline.sh <rds_path> <output_dir> [contrast1 contrast2 ...]
#
# What it does:
#   S0  sniff platform
#   S4  extract data via R script
#   S5  audit + placeholder for SKILL knowledge calls
#   S7  placeholder for quality gates
#   S8  write report stub (LLM synthesis done outside this script)
#
# This script handles the mechanical parts. The LLM-driven phases
# (S1 questions, S2 hypotheses, S3 plan, S6 synthesis) are still
# orchestrated by the gsealens-explorer subagent.

set -euo pipefail

if [ $# -lt 2 ]; then
    echo "Usage: $0 <rds_path> <output_dir> [contrasts...]"
    exit 1
fi

RDS_PATH="$1"
OUT_DIR="$2"
shift 2
CONTRASTS=("$@")

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PYTHON="${PYTHON:-python}"

# Ensure Rscript is on PATH (Windows + git-bash quirk)
# Try common install locations in priority order
for R_BIN in \
    "/c/Program Files/R/R-4.6.0/bin" \
    "/c/Program Files/R/R-4.5.0/bin" \
    "/c/Program Files/R/R-4.4.0/bin" \
    "/c/Program Files/R/R-4.3.0/bin" \
    "/c/Program Files/R/R-4.2.0/bin"; do
    if [ -x "$R_BIN/Rscript.exe" ] || [ -x "$R_BIN/Rscript" ]; then
        export PATH="$R_BIN:$PATH"
        break
    fi
done

R="${R:-Rscript}"

mkdir -p "$OUT_DIR"
LOG_DIR="$OUT_DIR"
AUDIT_LOG="$OUT_DIR/audit.log"
AUDIT_JSONL="$OUT_DIR/audit.jsonl"

ts() { date +"%Y-%m-%d %H:%M:%S"; }
log() { echo "[$(ts)] $*"; }

# ============== S0: Sniff platform ==============
log "=== S0: Sniff platform ==="
PLATFORM=$("$R" "$SCRIPT_DIR/sniff_platform.R" "$RDS_PATH" 2>&1 | grep -E "^(gsealens|enrichit|clusterprofiler|fgsea|unknown|ERROR)" | head -1)
SNIFF_EXIT=$?
log "Platform: $PLATFORM (exit=$SNIFF_EXIT)"

if [ "$SNIFF_EXIT" -ne 0 ]; then
    log "ERROR: platform detection failed"
    exit 1
fi

# ============== S4: Extract data ==============
log "=== S4: Extract data ==="
CONTRAST_ARGS=""
if [ ${#CONTRASTS[@]} -gt 0 ]; then
    CONTRAST_ARGS="${CONTRASTS[@]}"
fi
"$R" "$SCRIPT_DIR/extract_gsea_capsule.R" "$RDS_PATH" "$OUT_DIR" $CONTRAST_ARGS
EXTRACT_EXIT=$?
log "Extract exit code: $EXTRACT_EXIT"

if [ "$EXTRACT_EXIT" -ne 0 ]; then
    log "ERROR: extraction failed (exit=$EXTRACT_EXIT)"
    exit 2
fi

# ============== S5: Knowledge scaffolding (placeholder) ==============
log "=== S5: Knowledge scaffolding ==="
mkdir -p "$OUT_DIR/evidence"
# Placeholder for SKILL calls — actual calls done by subagent
cat > "$OUT_DIR/evidence/README.md" << 'EOF'
# Knowledge evidence directory

This directory holds output from cross-SKILL calls in S5:
- `pathway_knowledge.json` — reactome-skill
- `go_terms.json` — quickgo-skill
- `target_disease.json` — gdm-opentargets-database
- `literature.json` — mcp_unified-acade (PubMed)
- `ppi_network.json` — gdm-string-database (optional)

These are populated by the gsealens-explorer subagent during S5.
EOF
log "Evidence dir created. Subagent will populate in S5."

# ============== S6: Synthesis (LLM) ==============
log "=== S6: Synthesis (LLM-driven) ==="
log "Subagent will write 01_synthesis_draft.md here."
log "(This script does NOT call LLM; that's the subagent's job.)"

# ============== S7: Quality gates ==============
log "=== S7: Quality gates (run after LLM writes synthesis) ==="
log "After subagent writes 01_synthesis_draft.md, run:"
log "  $PYTHON $SCRIPT_DIR/quality_gate_check.py $OUT_DIR/01_synthesis_draft.md $OUT_DIR"

# ============== S8: Output ==============
log "=== S8: Output ==="
log "Subagent will write 01_exploratory_analysis_report.md after gates pass."

# ============== Done ==============
log "=== Mechanical pipeline complete ==="
log "Next steps (subagent):"
log "  1. S1 — ask user 5 critical questions, write metadata.json"
log "  2. S2 — generate 3-5 hypotheses, let user pick"
log "  3. S3 — confirm analysis plan"
log "  4. S5 — call cross-SKILL tools, populate evidence/"
log "  5. S6 — write 01_synthesis_draft.md"
log "  6. S7 — run quality_gate_check.py"
log "  7. S8 — finalize 01_exploratory_analysis_report.md"

log "Output files in: $OUT_DIR"
ls -la "$OUT_DIR"
