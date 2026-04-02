# Deploy process-invoice Edge Function (Document AI pipeline). Uses SUPABASE_ACCESS_TOKEN from .env.
$ErrorActionPreference = "Stop"
$projectRoot = Split-Path -Parent $PSScriptRoot
Set-Location $projectRoot

$envPath = Join-Path $projectRoot ".env"
if (Test-Path $envPath) {
  Get-Content $envPath | ForEach-Object {
    $line = $_.Trim()
    if ($line -match '^\s*#' -or $line -eq "") { return }
    if ($line -match '^\s*SUPABASE_ACCESS_TOKEN\s*=\s*(.+)$') {
      $env:SUPABASE_ACCESS_TOKEN = $matches[1].Trim().Trim('"').Trim("'")
    }
  }
}

if (-not $env:SUPABASE_ACCESS_TOKEN) {
  Write-Host "Missing SUPABASE_ACCESS_TOKEN in .env" -ForegroundColor Red
  exit 1
}

Write-Host "Deploying process-invoice..." -ForegroundColor Cyan
npx supabase functions deploy process-invoice --project-ref wpzopkigbbldcfpxuvcm
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
Write-Host "Done." -ForegroundColor Green
