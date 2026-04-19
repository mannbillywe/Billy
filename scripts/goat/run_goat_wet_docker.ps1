<#
    run_goat_wet_docker.ps1
    -----------------------
    One-shot wet run: build image from your Downloads backend folder and run
    `python -m goat.cli run` for a single user UUID. Writes to Supabase
    (goat_mode_jobs, goat_mode_snapshots, goat_mode_job_events,
    goat_mode_recommendations).

    Backend folder defaults to C:\Users\mannt\Downloads\backend (NOT billy_con\backend).

    Example:
      .\scripts\goat\run_goat_wet_docker.ps1 -UserId '3d8238ac-97bd-49e5-9ee7-1966447bae7c'

    Requires C:\Users\mannt\Downloads\backend\app\.env with SUPABASE_URL and
    SUPABASE_SERVICE_ROLE_KEY (service role JWT).
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, HelpMessage = 'Supabase auth user id = public.profiles.id')]
    [string]$UserId,

    [string]$BackendDir = 'C:\Users\mannt\Downloads\backend',
    [string]$ImageTag   = 'billy-goat-backend:latest',
    [string]$Scope      = 'full',
    [switch]$SkipBuild
)

$ErrorActionPreference = 'Stop'
$UserId = $UserId.Trim()
if (-not $UserId) { throw 'UserId is empty.' }

if (-not (Test-Path $BackendDir)) {
    throw "Backend folder not found: $BackendDir"
}
$envPath = Join-Path $BackendDir 'app\.env'
if (-not (Test-Path $envPath)) {
    throw "Missing $envPath — copy app\.env.example and fill SUPABASE_SERVICE_ROLE_KEY."
}

if (-not $SkipBuild) {
    Write-Host "[>] docker build -t $ImageTag $BackendDir" -ForegroundColor Cyan
    docker build -t $ImageTag $BackendDir
    if ($LASTEXITCODE -ne 0) { throw 'docker build failed' }
}

Write-Host "[>] docker run … goat.cli run --user-id $UserId --scope $Scope" -ForegroundColor Cyan
$dockerArgs = @(
    'run', '--rm',
    '--env-file', $envPath,
    $ImageTag,
    'python', '-m', 'goat.cli', 'run',
    '--user-id', $UserId,
    '--scope', $Scope,
    '--pretty'
)
& docker @dockerArgs
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
Write-Host '[v] Wet run finished — check Supabase goat_mode_snapshots for this user.' -ForegroundColor Green
