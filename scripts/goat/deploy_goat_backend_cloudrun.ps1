# Deploy (or update) the Billy AI Goat backend to Cloud Run.
#
# Works WITH the existing service's Secret Manager bindings. It:
#   1. Ensures SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, GEMINI_API_KEY, and
#      GOAT_BACKEND_SHARED_SECRET exist in GCP Secret Manager (creating them
#      if needed) and adds a new version with the value from backend/app/.env.
#   2. Updates the Cloud Run service with:
#        --update-secrets        (secret-backed env vars)
#        --update-env-vars       (plain flags like GOAT_AI_ENABLED)
#      so existing secret bindings are preserved.
#
# Requires: gcloud authenticated with roles/run.admin, roles/secretmanager.admin,
#           roles/iam.serviceAccountUser, and roles/cloudbuild.builds.editor.
#
# Usage:
#   gcloud auth login         # one-time
#   .\scripts\goat\deploy_goat_backend_cloudrun.ps1

# gcloud writes many informational messages to stderr. Using "Stop" causes
# PowerShell to abort on the first native-stderr write, even on success. We
# use Continue and check $LASTEXITCODE explicitly.
$ErrorActionPreference = "Continue"
$projectRoot = Split-Path -Parent $PSScriptRoot | Split-Path -Parent
Set-Location $projectRoot

if (-not $env:GCP_PROJECT)       { $env:GCP_PROJECT       = 'billy-ai-493507' }
if (-not $env:CLOUDRUN_REGION)   { $env:CLOUDRUN_REGION   = 'asia-south1' }
if (-not $env:CLOUDRUN_SERVICE)  { $env:CLOUDRUN_SERVICE  = 'billy-ai' }

$backendDir  = Join-Path $projectRoot "backend"
$envFilePath = Join-Path $projectRoot "backend\app\.env"

if (-not (Test-Path (Join-Path $backendDir "Dockerfile"))) {
  throw "Dockerfile not found at $backendDir\Dockerfile"
}
if (-not (Test-Path $envFilePath)) {
  throw "backend/app/.env not found - copy from .env.example and fill in secrets."
}

function Get-EnvValue([string]$key) {
  $line = (Get-Content $envFilePath | Where-Object { $_ -match "^\s*$([regex]::Escape($key))\s*=" } | Select-Object -First 1)
  if (-not $line) { return $null }
  $val = $line -replace "^\s*$([regex]::Escape($key))\s*=\s*", ""
  return $val.Trim().Trim('"').Trim("'")
}

$supabaseUrl   = Get-EnvValue 'SUPABASE_URL'
$supabaseKey   = Get-EnvValue 'SUPABASE_SERVICE_ROLE_KEY'
$geminiKey     = Get-EnvValue 'GEMINI_API_KEY'
$sharedSecret  = Get-EnvValue 'GOAT_BACKEND_SHARED_SECRET'
$aiModel       = Get-EnvValue 'GOAT_AI_MODEL'
if (-not $aiModel) { $aiModel = 'gemini-2.5-flash-lite' }

foreach ($pair in @(
  @('SUPABASE_URL',              $supabaseUrl),
  @('SUPABASE_SERVICE_ROLE_KEY', $supabaseKey),
  @('GEMINI_API_KEY',            $geminiKey),
  @('GOAT_BACKEND_SHARED_SECRET',$sharedSecret)
)) {
  if (-not $pair[1]) {
    throw "Missing $($pair[0]) in backend/app/.env"
  }
}

Write-Host "== Pushing Secret Manager versions ==" -ForegroundColor Cyan

function Ensure-Secret([string]$name, [string]$value) {
  $prevErr = $ErrorActionPreference
  $ErrorActionPreference = 'Continue'
  $null = & gcloud secrets describe $name --project=$env:GCP_PROJECT 2>&1
  $describeExit = $LASTEXITCODE
  $ErrorActionPreference = $prevErr
  if ($describeExit -ne 0) {
    Write-Host "  creating secret $name" -ForegroundColor DarkGray
    & gcloud secrets create $name --project=$env:GCP_PROJECT --replication-policy=automatic --quiet | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "Failed to create secret $name" }
  }
  $tmp = New-TemporaryFile
  $tmpPath = $tmp.FullName
  try {
    # Write value as UTF-8 without BOM to avoid trailing bytes.
    [IO.File]::WriteAllText($tmpPath, $value, (New-Object System.Text.UTF8Encoding($false)))
    & gcloud secrets versions add $name --project=$env:GCP_PROJECT "--data-file=$tmpPath" --quiet | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "Failed to add version to secret $name" }
    Write-Host "  $name : new version added" -ForegroundColor DarkGray
  } finally {
    Remove-Item -Force -ErrorAction SilentlyContinue $tmpPath
  }
}

Ensure-Secret 'SUPABASE_URL'              $supabaseUrl
Ensure-Secret 'SUPABASE_SERVICE_ROLE_KEY' $supabaseKey
Ensure-Secret 'GEMINI_API_KEY'            $geminiKey
Ensure-Secret 'GOAT_BACKEND_SHARED_SECRET' $sharedSecret

# Grant the Cloud Run runtime SA access to each secret (idempotent).
Write-Host ""
Write-Host "== Granting Cloud Run SA secretAccessor on each secret ==" -ForegroundColor Cyan
$runtimeSa = & gcloud run services describe $env:CLOUDRUN_SERVICE `
  --project=$env:GCP_PROJECT --region=$env:CLOUDRUN_REGION `
  --format="value(spec.template.spec.serviceAccountName)" 2>$null
if (-not $runtimeSa) {
  # Default compute SA if the service isn't using a custom one.
  $projNum = & gcloud projects describe $env:GCP_PROJECT --format="value(projectNumber)"
  $runtimeSa = "$projNum-compute@developer.gserviceaccount.com"
}
Write-Host "  runtime SA: $runtimeSa"

$prevErr = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
foreach ($s in @('SUPABASE_URL','SUPABASE_SERVICE_ROLE_KEY','GEMINI_API_KEY','GOAT_BACKEND_SHARED_SECRET')) {
  $null = & gcloud secrets add-iam-policy-binding $s `
    --project=$env:GCP_PROJECT `
    --member="serviceAccount:$runtimeSa" `
    --role=roles/secretmanager.secretAccessor `
    --quiet 2>&1
}
$ErrorActionPreference = $prevErr

Write-Host ""
Write-Host "== Deploying to Cloud Run ==" -ForegroundColor Cyan
Write-Host "  project : $env:GCP_PROJECT"
Write-Host "  region  : $env:CLOUDRUN_REGION"
Write-Host "  service : $env:CLOUDRUN_SERVICE"
Write-Host "  ai model: $aiModel"

$envVars = @(
  "GOAT_AI_ENABLED=1",
  "GOAT_AI_FAKE_MODE=0",
  "GOAT_AI_MODEL=$aiModel",
  "GOAT_REQUIRE_SHARED_SECRET=1",
  "GOAT_ALLOW_DEV_ENDPOINTS=0"
) -join ","

$secretBindings = @(
  "SUPABASE_URL=SUPABASE_URL:latest",
  "SUPABASE_SERVICE_ROLE_KEY=SUPABASE_SERVICE_ROLE_KEY:latest",
  "GEMINI_API_KEY=GEMINI_API_KEY:latest",
  "GOAT_BACKEND_SHARED_SECRET=GOAT_BACKEND_SHARED_SECRET:latest"
) -join ","

& gcloud run deploy $env:CLOUDRUN_SERVICE `
  --project=$env:GCP_PROJECT `
  --region=$env:CLOUDRUN_REGION `
  --source=$backendDir `
  --allow-unauthenticated `
  --port=8080 `
  --memory=1Gi `
  --cpu=1 `
  --timeout=300 `
  --update-env-vars=$envVars `
  --update-secrets=$secretBindings `
  --quiet
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host ""
Write-Host "Deployed. Probing /health ..." -ForegroundColor Green
$svcUrl = & gcloud run services describe $env:CLOUDRUN_SERVICE `
  --project=$env:GCP_PROJECT `
  --region=$env:CLOUDRUN_REGION `
  --format="value(status.url)"
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host "  service URL: $svcUrl"
$health = Invoke-RestMethod -Uri "$svcUrl/health" -TimeoutSec 30
$health | ConvertTo-Json -Depth 4

Write-Host ""
Write-Host "Next step - set GOAT_BACKEND_URL in Supabase function secrets:" -ForegroundColor Yellow
Write-Host "  `$env:GOAT_BACKEND_URL = '$svcUrl'"
Write-Host "  .\scripts\goat\deploy_goat_mode_trigger.ps1"
