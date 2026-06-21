# run_full_pipeline.ps1 — Windows driver for S0→S4 mechanical parts (gsealens-explorer v0.2.1)
#
# R execution policy (per r-interactive skill):
#   - All R calls go through the R-UTF8 PowerShell alias (provided by
#     r-interactive skill), which:
#       1. Sets $env:PWD = 'D:/' (bypasses Chinese-cwd encoding bug)
#       2. Adds --encoding=UTF-8 to Rscript (handles Chinese output)
#       3. Avoids R parser ambiguity in nested if-else under Chinese locale
#   - For truly stateful work, the subagent (or user) should source
#     the script inside an interactive R REPL.
#
# Usage:
#   powershell -ExecutionPolicy Bypass -File run_full_pipeline.ps1 `
#       -RdsPath "path\to\GSEA_Capsule.rds" `
#       -OutputDir ".\out" `
#       -Contrasts "AduCre_vs_Con","AgeCre_vs_Con","AgeCre_vs_AduCre"
#
# OR use env vars (for wrappers that hit Chinese-path encoding issues):
#   $env:GSEA_RDS = "<rds_path>"
#   $env:GSEA_OUT = "<output_dir>"
#   $env:GSEA_CONTRASTS = "AduCre_vs_Con,AgeCre_vs_Con,AgeCre_vs_AduCre"
#   powershell -ExecutionPolicy Bypass -File run_full_pipeline.ps1
#
# Requires: r-interactive skill (provides R-UTF8 alias)
#
# Mechanical phases handled here:
#   S0  sniff platform (Rscript one-shot)
#   S4  extract data (Rscript; for stateful use, source in R REPL)
#   S5  scaffold evidence/ directory
# S1-S3 and S6-S8 are LLM-driven, handled by gsealens-explorer subagent.

param(
    [Parameter(Mandatory = $false)] [string] $RdsPath = "",
    [Parameter(Mandatory = $false)] [string] $OutputDir = "",
    [string[]] $Contrasts = @(),
    [string] $Python = "",
    [string] $Rscript = ""
)

# Fall back to env vars (set by wrapper to bypass encoding bug)
if (-not $RdsPath -and $env:GSEA_RDS) { $RdsPath = $env:GSEA_RDS }
if (-not $OutputDir -and $env:GSEA_OUT) { $OutputDir = $env:GSEA_OUT }
if (-not $Python -and $env:GSEA_PYTHON) { $Python = $env:GSEA_PYTHON }
if (-not $Rscript -and $env:GSEA_RSCRIPT) { $Rscript = $env:GSEA_RSCRIPT }

# If Contrasts is a single comma-joined string (common when passing through
# `&` splat or non-array parameter), split it. Always do this.
if ($Contrasts.Count -eq 1 -and $Contrasts[0] -match ',') {
    $Contrasts = $Contrasts[0] -split ","
}

# If still empty, try env var
if ($Contrasts.Count -eq 0 -and $env:GSEA_CONTRASTS) {
    $Contrasts = $env:GSEA_CONTRASTS -split ","
}

$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

# Ensure R-UTF8 alias is loaded (from r-interactive skill's $PROFILE)
# When this script is run via -File, $PROFILE is NOT auto-loaded.
$profilePaths = @(
    "$env:USERPROFILE\Documents\PowerShell\Microsoft.PowerShell_profile.ps1",
    "$env:USERPROFILE\OneDrive\Documents\PowerShell\Microsoft.PowerShell_profile.ps1",
    "$PSHOME\Profile.ps1"
)
foreach ($p in $profilePaths) {
    if (Test-Path $p) {
        . $p 2>$null
        break
    }
}
if (-not (Get-Command R-UTF8 -ErrorAction SilentlyContinue)) {
    Write-Warning "R-UTF8 alias not found. Install r-interactive skill or source the profile manually."
}

# Mandatory parameter check (after env var fallback)
if (-not $RdsPath)   { throw "RdsPath required (use -RdsPath or env GSEA_RDS)" }
if (-not $OutputDir) { throw "OutputDir required (use -OutputDir or env GSEA_OUT)" }

# === Helpers ===
function Log($msg) {
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Output "[$ts] $msg"
}

function Locate-Tool {
    param([string]$Cmd, [string[]]$Candidates, [string]$Purpose, [string]$ParamName)
    # Test-Path with [System.IO.File]::Exists avoids mojibake on Chinese paths
    function Test-Exists([string]$p) {
        if (-not $p) { return $false }
        if ($p -match '^[A-Za-z]:[\\/]') {
            return [System.IO.File]::Exists($p)
        }
        return Test-Path $p
    }
    if ($Cmd -and (Test-Exists $Cmd)) { return $Cmd }
    if ($Cmd -and (Get-Command $Cmd -ErrorAction SilentlyContinue)) { return $Cmd }
    foreach ($p in $Candidates) {
        if (Test-Exists $p) { return $p }
    }
    throw "$Purpose not found. Pass -$ParamName path."
}

# R executable discovery. Prefer the first available install; user can override
# via -Rscript or $env:GSEA_RSCRIPT. Both 32-bit and 64-bit Rscript.exe work,
# but 64-bit is preferred for large (>100 MB) RDS files.
$DefaultRscript = @(
    "$env:GSEA_RSCRIPT",
    (Get-Command Rscript.exe -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source),
    "C:\Program Files\R\R-4.6.0\bin\x64\Rscript.exe",
    "C:\Program Files\R\R-4.5.0\bin\x64\Rscript.exe",
    "C:\Program Files\R\R-4.4.0\bin\x64\Rscript.exe",
    "/usr/bin/Rscript",
    "/usr/local/bin/Rscript"
) | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1
$DefaultPython = @(
    "$env:GSEA_PYTHON",
    (Get-Command python.exe -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source),
    (Get-Command python3.exe -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source),
    "python"
) | Where-Object { $_ } | Select-Object -First 1

$Rscript = Locate-Tool -Cmd $Rscript -Candidates $DefaultRscript -Purpose "Rscript" -ParamName "Rscript"
$Python  = Locate-Tool -Cmd $Python  -Candidates $DefaultPython -Purpose "Python" -ParamName "Python"
Log "Rscript: $Rscript"
Log "Python:  $Python"

# === Setup output dir ===
if (-not (Test-Path $OutputDir)) {
    New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null
}

# ============== S0: Sniff platform ==============
Log "=== S0: Sniff platform ==="
# Use Rscript directly with $env:PWD trick (from R-UTF8) to avoid Chinese cwd issue
# Don't use R-UTF8 here — it adds --encoding=UTF-8 which breaks wrapper files
$origPwd = $env:PWD
$env:PWD = 'D:/'
$sniffOut = & $Rscript "$ScriptDir\sniff_platform.R" $RdsPath 2>&1
$env:PWD = $origPwd
$sniffExit = $LASTEXITCODE
Log "Sniff exit:   $sniffExit"

if ($sniffExit -ne 0) {
    Log "ERROR: platform detection failed (sniff output: $sniffOut)"
    exit 1
}
# Pick first matching platform token (use exact match without anchor in case of mojibake)
$Platform = $null
foreach ($candidate in "gsealens","enrichit","clusterprofiler","fgsea") {
    if ($sniffOut -match $candidate) { $Platform = $candidate; break }
}
if (-not $Platform) {
    Log "ERROR: could not parse platform from sniff output: $sniffOut"
    exit 1
}
Log "Detected platform: $Platform"

if ($Platform -ne "gsealens") {
    Log "WARNING: only gsealens is fully supported. Got: $Platform"
}

# ============== S4: Extract data ==============
Log "=== S4: Extract data ==="

# Determine contrasts
if ($Contrasts.Count -gt 0) {
    $cnames = $Contrasts
} elseif ($env:GSEA_CONTRASTS) {
    $cnames = $env:GSEA_CONTRASTS -split ","
} else {
    $cnames = @()
}

# Call extract script directly via Rscript (same pattern as sniff — no wrapper needed)
# Use $env:PWD trick to avoid Chinese cwd crash
$origPwd = $env:PWD
$env:PWD = 'D:/'
$allArgs = @("$ScriptDir\extract_gsea_capsule.R", $RdsPath, $OutputDir) + $cnames
& $Rscript @allArgs 2>&1 | ForEach-Object { Log $_ }
$env:PWD = $origPwd
$extractExit = $LASTEXITCODE
Log "Extract exit: $extractExit"

if ($extractExit -ne 0) {
    Log "ERROR: extraction failed (exit=$extractExit)"
    exit 2
}

# ============== S5: Evidence scaffolding ==============
Log "=== S5: Evidence scaffolding ==="
$evidenceDir = Join-Path $OutputDir "evidence"
if (-not (Test-Path $evidenceDir)) {
    New-Item -ItemType Directory -Force -Path $evidenceDir | Out-Null
}
$readmePath = Join-Path $evidenceDir "README.md"
$readmeContent = @"
# Knowledge evidence directory (S5 outputs)

The gsealens-explorer subagent will populate this with:
- pathway_knowledge.json — reactome-skill output
- go_terms.json          — quickgo-skill output
- target_disease.json    — gdm-opentargets-database output
- literature.json        — mcp_unified-acade (PubMed) output
- ppi_network.json       — gdm-string-database output (optional)
"@
Set-Content -Path $readmePath -Value $readmeContent -Encoding utf8
Log "Evidence dir created: $evidenceDir"

# ============== Done ==============
Log "=== Mechanical pipeline complete ==="
Log "Output dir: $OutputDir"
Get-ChildItem $OutputDir | Format-Table Name, Length -AutoSize
Log ""
Log "Next steps (handled by gsealens-explorer subagent):"
Log "  S1  ask user 5 critical questions, write metadata.json"
Log "  S2  generate 3-5 hypotheses, let user pick"
Log "  S3  confirm analysis plan"
Log "  S5  call cross-SKILL tools, populate evidence/"
Log "  S6  write 01_synthesis_draft.md"
Log "  S7  run quality_gate_check.py"
Log "  S8  finalize 01_exploratory_analysis_report.md"
Log ""
Log "R note: for stateful work, use 'r-interactive' skill:"
Log "  & 'C:\Program Files\R\R-4.6.0\bin\x64\R.exe' --interactive"
Log "  Then: source('${ScriptDir}\extract_gsea_capsule.R')"
