# Deploy process-invoice Edge Function (Document AI pipeline).
# Token: process env SUPABASE_ACCESS_TOKEN, else .env supabase1234, else .env SUPABASE_ACCESS_TOKEN.
$ErrorActionPreference = "Stop"
$projectRoot = Split-Path -Parent $PSScriptRoot
Set-Location $projectRoot

if (-not $env:SUPABASE_ACCESS_TOKEN) {
  $envPath = Join-Path $projectRoot ".env"
  if (Test-Path $envPath) {
    $pat = $null
    $patStd = $null
    Get-Content $envPath | ForEach-Object {
      $line = $_.Trim()
      if ($line -match '^\s*#' -or $line -eq "") { return }
      if ($line -match '^\s*supabase1234\s*=\s*(.+)$') {
        $pat = $matches[1].Trim().Trim('"').Trim("'")
      }
      if ($line -match '^\s*SUPABASE_ACCESS_TOKEN\s*=\s*(.+)$') {
        $patStd = $matches[1].Trim().Trim('"').Trim("'")
      }
    }
    if ($pat) { $env:SUPABASE_ACCESS_TOKEN = $pat }
    elseif ($patStd) { $env:SUPABASE_ACCESS_TOKEN = $patStd }
  }
}

if (-not $env:SUPABASE_ACCESS_TOKEN) {
  Write-Host "Missing PAT: set SUPABASE_ACCESS_TOKEN or supabase1234 in .env (or export SUPABASE_ACCESS_TOKEN)." -ForegroundColor Red
  exit 1
}

Write-Host "Deploying process-invoice..." -ForegroundColor Cyan
npx supabase functions deploy process-invoice --project-ref wpzopkigbbldcfpxuvcm
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
Write-Host "Done." -ForegroundColor Green
