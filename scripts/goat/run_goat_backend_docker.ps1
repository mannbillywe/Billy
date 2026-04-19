<#
    run_goat_backend_docker.ps1
    ---------------------------
    Rebuilds the GOAT Mode backend Docker image from C:\Users\mannt\Downloads\backend
    and runs the in-container CLI once per UUID. Each run is a wet-run — results
    are persisted into Supabase (goat_mode_jobs / goat_mode_snapshots /
    goat_mode_job_events / goat_mode_recommendations).

    HOW TO USE
        1. Paste one or more user UUIDs into the $UserIds array below.
        2. (First time only) ensure C:\Users\mannt\Downloads\backend\app\.env has:
             SUPABASE_URL=...
             SUPABASE_SERVICE_ROLE_KEY=<service_role JWT — NOT the anon key>
             GOAT_BACKEND_SHARED_SECRET=<random 48-byte hex>
             GOAT_AI_ENABLED=1          # optional
             GEMINI_API_KEY=...         # only if GOAT_AI_ENABLED=1
        3. Run this script from PowerShell:
             .\scripts\goat\run_goat_backend_docker.ps1

    WHAT IT DOES
        * docker build -t billy-goat-backend:latest  (against the Downloads folder)
        * for each UUID: docker run --rm … python -m goat.cli run
            --user-id <uid> --scope full --pretty
          (no --dry-run, so writes land in Supabase)
        * Saves the raw JSON response to .tools\goat-runs\<timestamp>-<uid>.json
          for debugging.

    REQUIREMENTS
        * Docker Desktop running
        * User profiles must already exist in public.profiles
        * You may want to run scripts\goat\grant_goat_mode_access.sql for these
          UUIDs too, so the Flutter UI shows the GOAT Mode button afterwards.
#>

[CmdletBinding()]
param(
    [string]$BackendDir = 'C:\Users\mannt\Downloads\backend',
    [string]$ImageTag   = 'billy-goat-backend:latest',
    [string]$Scope      = 'full',
    [switch]$SkipBuild
)

$ErrorActionPreference = 'Stop'

# ────────────────────── EDIT THIS LIST ──────────────────────
# Paste Supabase Auth user UUIDs (same as public.profiles.id). One per line.
# For a single user from the shell, prefer: .\scripts\goat\run_goat_wet_docker.ps1 -UserId '<uuid>'
$UserIds = @(
    # '<PASTE-YOUR-USER-UUID-HERE>'
)
# ────────────────────────────────────────────────────────────

if (-not $UserIds -or $UserIds.Count -eq 0) {
    Write-Host '[!] No UUIDs supplied. Edit $UserIds at the top of this script.' -ForegroundColor Yellow
    exit 2
}

if (-not (Test-Path $BackendDir)) {
    throw "Backend folder not found: $BackendDir"
}

$envPath = Join-Path $BackendDir 'app\.env'
if (-not (Test-Path $envPath)) {
    throw "Missing $envPath — copy app\.env.example and fill SUPABASE_SERVICE_ROLE_KEY first."
}

# Quick sanity check on the env file: must carry the service-role JWT, NOT the
# anon key, otherwise every RLS read returns 0 rows and writes fail.
$envText = Get-Content $envPath -Raw
if ($envText -notmatch 'SUPABASE_SERVICE_ROLE_KEY=\S+') {
    throw "SUPABASE_SERVICE_ROLE_KEY is blank in $envPath. Paste the service_role JWT from the Supabase dashboard."
}

$repoRoot   = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$outDir     = Join-Path $repoRoot '.tools\goat-runs'
$null       = New-Item -ItemType Directory -Force -Path $outDir
$timestamp  = Get-Date -Format 'yyyyMMdd-HHmmss'

Write-Host "[i] backend dir : $BackendDir"
Write-Host "[i] image tag   : $ImageTag"
Write-Host "[i] scope       : $Scope"
Write-Host "[i] users       : $($UserIds.Count)"
Write-Host "[i] output dir  : $outDir"
Write-Host ''

# 1. Build
if ($SkipBuild) {
    Write-Host '[>] skipping docker build (--SkipBuild)'
} else {
    Write-Host "[>] docker build -t $ImageTag $BackendDir"
    & docker build -t $ImageTag $BackendDir
    if ($LASTEXITCODE -ne 0) { throw 'docker build failed' }
}
Write-Host ''

# 2. Run per UUID
$failed  = @()
$results = @()

foreach ($uid in $UserIds) {
    $uid = $uid.Trim()
    if (-not $uid) { continue }

    Write-Host "[>] running GOAT for $uid (scope=$Scope)..." -ForegroundColor Cyan

    $outFile = Join-Path $outDir "$timestamp-$uid.json"

    # Run the CLI inside a throwaway container. Override the default CMD.
    $args = @(
        'run', '--rm',
        '--env-file', $envPath,
        $ImageTag,
        'python', '-m', 'goat.cli', 'run',
        '--user-id', $uid,
        '--scope', $Scope,
        '--pretty'
    )

    try {
        $stdout = & docker @args 2>&1
        $code = $LASTEXITCODE
    } catch {
        Write-Host "    [x] docker invocation failed: $_" -ForegroundColor Red
        $failed += $uid
        continue
    }

    if ($code -ne 0) {
        Write-Host "    [x] run failed for $uid (exit $code)" -ForegroundColor Red
        $failed += $uid
        $stdout | Set-Content -Path $outFile -Encoding UTF8
        continue
    }

    # Try to slice out the JSON payload printed by cli.py (last {...} block).
    $joined = ($stdout -join "`n")
    $firstBrace = $joined.IndexOf('{')
    if ($firstBrace -ge 0) {
        $payload = $joined.Substring($firstBrace)
        Set-Content -Path $outFile -Value $payload -Encoding UTF8
    } else {
        Set-Content -Path $outFile -Value $joined -Encoding UTF8
    }

    # Best-effort parse so we can print a one-line summary.
    $summary = $null
    try {
        $json = $joined.Substring($firstBrace) | ConvertFrom-Json -ErrorAction Stop
        $summary = [pscustomobject]@{
            user_id          = $uid
            scope            = $json.scope
            readiness_level  = $json.readiness_level
            snapshot_status  = $json.snapshot_status
            recommendations  = $json.recommendation_count
            ai_mode          = $json.ai.mode
            snapshot_id      = $json.snapshot_id
        }
    } catch {
        $summary = [pscustomobject]@{ user_id = $uid; raw_only = $true }
    }
    $results += $summary

    Write-Host "    [v] $uid  readiness=$($summary.readiness_level) status=$($summary.snapshot_status) recs=$($summary.recommendations) ai=$($summary.ai_mode)" -ForegroundColor Green
    Write-Host "    [i] wrote $outFile"
}

Write-Host ''
Write-Host '───────────────────────────  summary  ───────────────────────────' -ForegroundColor DarkCyan
if ($results) { $results | Format-Table -AutoSize | Out-String | Write-Host }
if ($failed) {
    Write-Host "[x] $($failed.Count) user(s) FAILED:" -ForegroundColor Red
    $failed | ForEach-Object { Write-Host "    - $_" -ForegroundColor Red }
    exit 1
}
Write-Host '[v] done — snapshots are now in Supabase. Flutter clients will pick them up on next fetch.' -ForegroundColor Green
