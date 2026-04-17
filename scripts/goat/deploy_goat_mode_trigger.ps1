# Deploy the goat-mode-trigger Supabase Edge Function.
#
# Sets the function secrets (GOAT_BACKEND_URL, GOAT_BACKEND_SHARED_SECRET)
# from backend/app/.env + GCP Cloud Run URL, then deploys the function.
#
# SUPABASE_URL and SUPABASE_ANON_KEY are already provided to all Edge Functions
# by the Supabase platform - do not set them manually.
#
# Usage:
#   $env:GOAT_BACKEND_URL = 'https://billy-ai-xxxxx-xx.a.run.app'
#   .\scripts\goat\deploy_goat_mode_trigger.ps1

$ErrorActionPreference = "Stop"
$projectRoot = Split-Path -Parent $PSScriptRoot | Split-Path -Parent
Set-Location $projectRoot

# Use PAT from .env or process env.
if (-not $env:SUPABASE_ACCESS_TOKEN) {
  $envPath = Join-Path $projectRoot ".env"
  if (Test-Path $envPath) {
    $pat = $null; $patStd = $null
    Get-Content $envPath | ForEach-Object {
      $line = $_.Trim()
      if ($line -match '^\s*#' -or $line -eq "") { return }
      if ($line -match '^\s*supabase1234\s*=\s*(.+)$') { $pat = $matches[1].Trim().Trim('"').Trim("'") }
      if ($line -match '^\s*SUPABASE_ACCESS_TOKEN\s*=\s*(.+)$') { $patStd = $matches[1].Trim().Trim('"').Trim("'") }
    }
    if ($patStd) { $env:SUPABASE_ACCESS_TOKEN = $patStd }
    elseif ($pat) { $env:SUPABASE_ACCESS_TOKEN = $pat }
  }
}
if (-not $env:SUPABASE_ACCESS_TOKEN) {
  throw "No Supabase PAT in env or .env. Set SUPABASE_ACCESS_TOKEN, or run `supabase login`."
}

# Read the backend shared secret from backend/app/.env.
$envFilePath = Join-Path $projectRoot "backend\app\.env"
$line = (Get-Content $envFilePath | Where-Object { $_ -match '^\s*GOAT_BACKEND_SHARED_SECRET\s*=' } | Select-Object -First 1)
if (-not $line) { throw "GOAT_BACKEND_SHARED_SECRET missing from backend/app/.env" }
$sharedSecret = ($line -replace '^\s*GOAT_BACKEND_SHARED_SECRET\s*=\s*', '').Trim().Trim('"').Trim("'")

if (-not $env:GOAT_BACKEND_URL) {
  throw "Set `$env:GOAT_BACKEND_URL (from the Cloud Run service URL printed by the backend deploy script) before running this script."
}

# Optional: if .secrets\billy-goat-invoker.json exists, push it as
# GCP_INVOKER_SA_KEY so the Edge Function can mint an ID token for private
# Cloud Run invocation. If absent, we skip it and assume Cloud Run is
# --allow-unauthenticated + shared-secret protected.
$saKeyPath = Join-Path $projectRoot ".secrets\billy-goat-invoker.json"
$saKeyJson = $null
if (Test-Path $saKeyPath) {
  # Re-serialize as compact single-line JSON so it survives env-file parsing.
  $saKeyJson = (Get-Content $saKeyPath -Raw | ConvertFrom-Json | ConvertTo-Json -Compress -Depth 10)
  Write-Host "  GCP_INVOKER_SA_KEY=<$($saKeyJson.Length) chars> (from .secrets\billy-goat-invoker.json)"
} else {
  Write-Host "  GCP_INVOKER_SA_KEY: SKIPPED (no .secrets\billy-goat-invoker.json found)" -ForegroundColor Yellow
}

$projectRef = if ($env:SUPABASE_PROJECT_REF) { $env:SUPABASE_PROJECT_REF } else { "wpzopkigbbldcfpxuvcm" }

Write-Host "== Setting Edge Function secrets on $projectRef ==" -ForegroundColor Cyan
Write-Host "  GOAT_BACKEND_URL=$env:GOAT_BACKEND_URL"
Write-Host "  GOAT_BACKEND_SHARED_SECRET=<$($sharedSecret.Length) chars>"

# supabase CLI's `secrets set` accepts values inline, but JSON with newlines
# is fragile on PowerShell. Use --env-file instead when we have the SA key.
$tmpEnv = New-TemporaryFile
$tmpEnvPath = $tmpEnv.FullName
try {
  $lines = @(
    "GOAT_BACKEND_URL=$env:GOAT_BACKEND_URL",
    "GOAT_BACKEND_SHARED_SECRET=$sharedSecret"
  )
  if ($saKeyJson) {
    # $saKeyJson is already compact single-line JSON (no literal newlines).
    $lines += "GCP_INVOKER_SA_KEY=$saKeyJson"
  }
  # Supabase CLI rejects UTF-8-with-BOM env files. Write raw UTF-8 no-BOM.
  $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
  [IO.File]::WriteAllText($tmpEnvPath, (($lines -join "`n") + "`n"), $utf8NoBom)

  npx --yes supabase@latest secrets set --project-ref $projectRef --env-file $tmpEnvPath
  if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
} finally {
  Remove-Item -Force -ErrorAction SilentlyContinue $tmpEnvPath
}

Write-Host ""
Write-Host "== Deploying goat-mode-trigger ==" -ForegroundColor Cyan
# --no-verify-jwt: the Functions gateway only supports HS256 JWT verification,
# but this project uses asymmetric ES256 auth JWTs. The function body itself
# still validates users via supabase.auth.getUser(), so auth is preserved.
npx --yes supabase@latest functions deploy goat-mode-trigger --project-ref $projectRef --no-verify-jwt
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host ""
Write-Host "Done. Function URL:" -ForegroundColor Green
Write-Host "  https://$projectRef.functions.supabase.co/goat-mode-trigger"
