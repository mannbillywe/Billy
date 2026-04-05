# Deploy analytics-insights Edge Function to Supabase.
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
      if ($line -match '^\s*supabase1234\s*=\s*(.+)$') { $pat = $matches[1].Trim().Trim('"').Trim("'") }
      if ($line -match '^\s*SUPABASE_ACCESS_TOKEN\s*=\s*(.+)$') { $patStd = $matches[1].Trim().Trim('"').Trim("'") }
    }
    if ($pat) { $env:SUPABASE_ACCESS_TOKEN = $pat }
    elseif ($patStd) { $env:SUPABASE_ACCESS_TOKEN = $patStd }
  }
}

if (-not $env:SUPABASE_ACCESS_TOKEN) {
  Write-Host "No PAT: add supabase1234 or SUPABASE_ACCESS_TOKEN to .env, or run supabase login." -ForegroundColor Yellow
}

Write-Host "Deploying analytics-insights..." -ForegroundColor Cyan
npx --yes supabase@latest functions deploy analytics-insights --project-ref wpzopkigbbldcfpxuvcm
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
Write-Host "Done. Set GEMINI_API_KEY secret on the function if not already (Dashboard → Edge Functions → Secrets)." -ForegroundColor Green
