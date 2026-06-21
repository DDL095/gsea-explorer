# deploy_to_copilot.ps1 — Deploy (or refresh) the gsealens-explorer skill into the
# local Copilot skills directory, without clobbering personal overrides.
#
# Usage (PowerShell):
#   powershell -ExecutionPolicy Bypass -File deploy\deploy_to_copilot.ps1
#   powershell -ExecutionPolicy Bypass -File deploy\deploy_to_copilot.ps1 -Target "D:\custom\skills\gsealens-explorer"
#   powershell -ExecutionPolicy Bypass -File deploy\deploy_to_copilot.ps1 -DryRun
#
# Contract (see docs/architecture.md):
#   1. Copy every tracked file from this source repo into <Target>.
#   2. NEVER overwrite <Target>\.local_overrides\ (the personalization layer).
#   3. Do NOT copy .git\, tests\testdata\*.rds, or any source-side .local_overrides.
#   4. Report added / modified / removed counts.
#   5. Exit non-zero on any copy error.

[CmdletBinding()]
param(
    [string]$Target = "",

    [switch]$DryRun
)

$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path -Parent $PSScriptRoot

if (-not $Target) {
    $Target = Join-Path $env:USERPROFILE ".copilot\skills\gsealens-explorer"
}

# --- Pre-flight ---
if (-not (Test-Path $RepoRoot\SKILL.md)) {
    throw "RepoRoot looks wrong: $RepoRoot (no SKILL.md found)"
}

# Source-side ignore list (never copy these from the repo)
$SourceExcludes = @(
    '.git',
    '.gitignore',
    '.local_overrides',
    'tests\testdata',
    'node_modules',
    'out',
    '.audit'
)
# Target-side preserve list (never delete these in the target)
$TargetPreserve = @(
    '.local_overrides'
)

# --- Helpers ---
function Log($msg) {
    Write-Host "[$([DateTime]::Now.ToString('HH:mm:ss'))] $msg"
}

function Test-Excluded([string]$relativePath, [string[]]$excludes) {
    foreach ($ex in $excludes) {
        $exNorm = ($ex -replace '\\', '/') -replace '/$', ''
        if ($relativePath -like "$exNorm/*" -or $relativePath -eq $exNorm) {
            return $true
        }
        # Also match a leading segment
        $firstSeg = ($relativePath -split '/')[0]
        if ($firstSeg -eq $exNorm) { return $true }
    }
    return $false
}

# --- Enumerate source files ---
$allSourceFiles = Get-ChildItem -Path $RepoRoot -Recurse -File -Force |
    Where-Object {
        $rel = $_.FullName.Substring($RepoRoot.Length + 1) -replace '\\', '/'
        -not (Test-Excluded $rel $SourceExcludes)
    }

$sourcePlan = $allSourceFiles | ForEach-Object {
    $rel = $_.FullName.Substring($RepoRoot.Length + 1) -replace '\\', '/'
    [PSCustomObject]@{
        Relative = $rel
        Source   = $_.FullName
        Target   = Join-Path $Target ($rel -replace '/', '\')
        Size     = $_.Length
    }
}

Log "Source repo:   $RepoRoot"
Log "Deploy target: $Target"
Log "Mode:          $(if ($DryRun) { 'DRY-RUN (no writes)' } else { 'LIVE' })"
Log "Source files:  $($sourcePlan.Count)"
if (-not (Test-Path $Target)) {
    Log "Target does not exist yet; will create."
} else {
    $overrideDir = Join-Path $Target '.local_overrides'
    if (Test-Path $overrideDir) {
        Log "Preserve target\.local_overrides\ (personalization layer)"
    }
}

# --- Compute plan ---
$added    = @()
$modified = @()
$unchanged = @()

foreach ($p in $sourcePlan) {
    if (-not (Test-Path $p.Target)) {
        $added += $p
    } else {
        $tgtInfo = Get-Item $p.Target
        if ($tgtInfo.Length -ne $p.Size) {
            $modified += $p
        } else {
            # Same size; assume unchanged. (Robocopy-style content check could
            # be added here, but byte-level comparison on every run is slow.)
            $unchanged += $p
        }
    }
}

# --- Removals: target files not present in source (excluding preserved dirs) ---
$allTargetFiles = @()
if (Test-Path $Target) {
    $allTargetFiles = Get-ChildItem -Path $Target -Recurse -File -Force |
        Where-Object {
            $rel = $_.FullName.Substring($Target.Length + 1) -replace '\\', '/'
            -not (Test-Excluded $rel $TargetPreserve)
        }
}
$removed = @()
foreach ($tf in $allTargetFiles) {
    $rel = $tf.FullName.Substring($Target.Length + 1) -replace '\\', '/'
    if (-not ($sourcePlan | Where-Object { $_.Relative -eq $rel })) {
        $removed += [PSCustomObject]@{ Relative = $rel; Target = $tf.FullName }
    }
}

# --- Report ---
Log ""
Log "=== Plan ==="
Log ("Added:     {0}" -f $added.Count)
Log ("Modified:  {0}" -f $modified.Count)
Log ("Unchanged: {0}" -f $unchanged.Count)
Log ("Removed:   {0}" -f $removed.Count)

if ($added.Count -gt 0) {
    Log ""
    Log "[added]"
    $added | ForEach-Object { Log ("  + {0}" -f $_.Relative) }
}
if ($modified.Count -gt 0) {
    Log ""
    Log "[modified]"
    $modified | ForEach-Object { Log ("  ~ {0}" -f $_.Relative) }
}
if ($removed.Count -gt 0) {
    Log ""
    Log "[removed]"
    $removed | ForEach-Object { Log ("  - {0}" -f $_.Relative) }
}

if ($DryRun) {
    Log ""
    Log "Dry-run only; no files written. Re-run without -DryRun to deploy."
    return
}

# --- Execute ---
if (-not (Test-Path $Target)) {
    New-Item -ItemType Directory -Force -Path $Target | Out-Null
}

$opLog = Join-Path $Target '.audit'
if (-not (Test-Path $opLog)) {
    New-Item -ItemType Directory -Force -Path $opLog | Out-Null
}
$deployLog = Join-Path $opLog ("deploy_" + ([DateTime]::Now.ToString('yyyyMMdd_HHmmss')) + '.log')
function DeployLog($msg) {
    Add-Content -Path $deployLog -Value "[$([DateTime]::Now.ToString('yyyy-MM-dd HH:mm:ss'))] $msg"
}
DeployLog "deploy_to_copilot.ps1 start"
DeployLog "Source: $RepoRoot"
DeployLog "Target: $Target"

# Copy new + modified
foreach ($p in $added + $modified) {
    $tgtDir = Split-Path -Parent $p.Target
    if (-not (Test-Path $tgtDir)) {
        New-Item -ItemType Directory -Force -Path $tgtDir | Out-Null
        DeployLog "mkdir $tgtDir"
    }
    try {
        Copy-Item -Path $p.Source -Destination $p.Target -Force
        DeployLog ("copy  {0} -> {1}" -f $p.Relative, $p.Target)
    } catch {
        DeployLog ("ERROR copying {0}: {1}" -f $p.Relative, $_.Exception.Message)
        throw
    }
}

# Remove target-only files
foreach ($r in $removed) {
    try {
        Remove-Item -Path $r.Target -Force
        DeployLog ("rm    {0}" -f $r.Relative)
    } catch {
        DeployLog ("ERROR removing {0}: {1}" -f $r.Relative, $_.Exception.Message)
        throw
    }
}

DeployLog "deploy_to_copilot.ps1 done"
Log ""
Log "Deploy complete. Log written to: $deployLog"
Log "Personalization (.local_overrides\): preserved."
