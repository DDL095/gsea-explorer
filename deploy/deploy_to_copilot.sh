#!/usr/bin/env bash
# deploy_to_copilot.sh — Deploy (or refresh) the gsealens-explorer skill into the
# local Copilot skills directory, without clobbering personal overrides.
#
# Usage:
#   bash deploy/deploy_to_copilot.sh
#   bash deploy/deploy_to_copilot.sh --target ~/.copilot/skills/gsealens-explorer
#   bash deploy/deploy_to_copilot.sh --dry-run
#
# Contract (see docs/architecture.md):
#   1. Copy every tracked file from this source repo into <target>.
#   2. NEVER overwrite <target>/.local_overrides/ (the personalization layer).
#   3. Do NOT copy .git/, tests/testdata/*.rds, or any source-side .local_overrides.
#   4. Report added / modified / removed counts.
#   5. Exit non-zero on any copy error.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGET="${HOME}/.copilot/skills/gsealens-explorer"
DRY_RUN=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --target) TARGET="$2"; shift 2 ;;
        --dry-run) DRY_RUN=1; shift ;;
        -h|--help)
            sed -n '2,15p' "${BASH_SOURCE[0]}"
            exit 0
            ;;
        *) echo "Unknown argument: $1" >&2; exit 2 ;;
    esac
done

# --- Pre-flight ---
if [[ ! -f "${REPO_ROOT}/SKILL.md" ]]; then
    echo "ERROR: REPO_ROOT looks wrong: ${REPO_ROOT} (no SKILL.md found)" >&2
    exit 1
fi

# Source-side ignore list (relative to REPO_ROOT). rsync will skip these.
SOURCE_EXCLUDES=(
    '.git'
    '.gitignore'
    '.local_overrides'
    'tests/testdata'
    'node_modules'
    'out'
    '.audit'
)

# --- Helpers ---
log() { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*"; }

EXCLUDE_ARGS=()
for ex in "${SOURCE_EXCLUDES[@]}"; do
    EXCLUDE_ARGS+=(--exclude="${ex}")
done

# --- Compute plan (dry-run first to show what will happen) ---
log "Source repo:   ${REPO_ROOT}"
log "Deploy target: ${TARGET}"
if (( DRY_RUN )); then
    log "Mode:          DRY-RUN (no writes)"
else
    log "Mode:          LIVE"
fi
log ""

if [[ ! -d "${TARGET}" ]]; then
    log "Target does not exist yet; will create."
fi

OVERRIDE_DIR="${TARGET}/.local_overrides"
if [[ -d "${OVERRIDE_DIR}" ]]; then
    log "Preserve ${OVERRIDE_DIR} (personalization layer)"
fi

log "=== Plan (rsync --dry-run -rn) ==="
rsync -rn --itemize-changes "${EXCLUDE_ARGS[@]}" \
    --exclude='.local_overrides' \
    "${REPO_ROOT}/" "${TARGET}/" || true
log ""

if (( DRY_RUN )); then
    log "Dry-run only; no files written. Re-run without --dry-run to deploy."
    exit 0
fi

# --- Execute live deploy ---
mkdir -p "${TARGET}"
AUDIT_DIR="${TARGET}/.audit"
mkdir -p "${AUDIT_DIR}"
DEPLOY_LOG="${AUDIT_DIR}/deploy_$(date +%Y%m%d_%H%M%S).log"

{
    echo "[$(date '+%F %T')] deploy_to_copilot.sh start"
    echo "Source: ${REPO_ROOT}"
    echo "Target: ${TARGET}"
} | tee -a "${DEPLOY_LOG}" >/dev/null

# rsync handles add/modify/remove atomically while preserving .local_overrides
rsync -r --itemize-changes \
    "${EXCLUDE_ARGS[@]}" \
    --exclude='.local_overrides' \
    --delete \
    "${REPO_ROOT}/" "${TARGET}/" 2>&1 | tee -a "${DEPLOY_LOG}" || {
        echo "ERROR: rsync failed" >&2
        exit 1
    }

{
    echo "[$(date '+%F %T')] deploy_to_copilot.sh done"
} >> "${DEPLOY_LOG}"

log ""
log "Deploy complete. Log: ${DEPLOY_LOG}"
log "Personalization (.local_overrides/): preserved."
