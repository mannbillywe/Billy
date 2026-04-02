# Deploy analytics-insights Edge Function to Supabase.
# Prerequisites: npm (for npx supabase), and either:
#   - supabase login
#   - or set SUPABASE_ACCESS_TOKEN (Dashboard → Account → Access tokens)

$ErrorActionPreference = "Stop"
$projectRoot = Split-Path -Parent $PSScriptRoot
Set-Location $projectRoot

if (-not $env:SUPABASE_ACCESS_TOKEN) {
    Write-Host "SUPABASE_ACCESS_TOKEN not set. Run: supabase login" -ForegroundColor Yellow
    Write-Host "Or: `$env:SUPABASE_ACCESS_TOKEN = 'your-token'" -ForegroundColor Gray
}

Write-Host "Deploying analytics-insights..." -ForegroundColor Cyan
npx --yes supabase@latest functions deploy analytics-insights --project-ref wpzopkigbbldcfpxuvcm
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
Write-Host "Done. Set GEMINI_API_KEY secret on the function if not already (Dashboard → Edge Functions → Secrets)." -ForegroundColor Green
