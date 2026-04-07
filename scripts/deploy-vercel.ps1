# Deploy Billy Flutter web app to Vercel
# Prerequisites: Flutter SDK, Vercel CLI (npm i -g vercel)
# Set VERCEL_TOKEN env var with your token, or run: vercel login

$ErrorActionPreference = "Stop"
$projectRoot = Split-Path -Parent $PSScriptRoot
$buildWeb = Join-Path $projectRoot "build\web"

Write-Host "Building Flutter web..." -ForegroundColor Cyan
Set-Location $projectRoot
$flutter = Get-Command flutter -ErrorAction SilentlyContinue
if (-not $flutter) {
    Write-Host "flutter not on PATH. Install Flutter or add it to PATH." -ForegroundColor Red
    exit 1
}
# Optional: config/prod.json with SUPABASE_URL, SUPABASE_ANON_KEY, SENTRY_DSN (see config/example.json)
$defineFile = Join-Path $projectRoot "config\prod.json"
$defineArgs = @()
if (Test-Path $defineFile) {
    $defineArgs = @("--dart-define-from-file=$defineFile")
    Write-Host "Using dart-define-from-file: config\prod.json" -ForegroundColor Gray
}
# Vercel Dashboard: set SUPABASE_URL and SUPABASE_ANON_KEY on the project so release builds embed the right project.
$envDefines = @()
if ($env:SUPABASE_URL -and $defineArgs.Count -eq 0) {
    $envDefines += "--dart-define=SUPABASE_URL=$($env:SUPABASE_URL)"
    Write-Host "Using SUPABASE_URL from environment" -ForegroundColor Gray
}
if ($env:SUPABASE_ANON_KEY -and $defineArgs.Count -eq 0) {
    $envDefines += "--dart-define=SUPABASE_ANON_KEY=$($env:SUPABASE_ANON_KEY)"
    Write-Host "Using SUPABASE_ANON_KEY from environment" -ForegroundColor Gray
}
if ($env:SENTRY_DSN) {
    $envDefines += "--dart-define=SENTRY_DSN=$($env:SENTRY_DSN)"
    Write-Host "Using SENTRY_DSN from environment" -ForegroundColor Gray
}
# --no-wasm-dry-run: quieter CI/local logs (Flutter 3.27+ wasm dry run notice).
# Avoid deploying from web/ without a build — see README.md (Vercel section).
& flutter build web --release @defineArgs @envDefines --no-wasm-dry-run
if ($LASTEXITCODE -ne 0) {
    Write-Host "If the error mentions symlink support: enable Windows Developer Mode (Settings → System → For developers)." -ForegroundColor Yellow
    exit $LASTEXITCODE
}

# SPA fallback for Flutter web client routing
$vercelSrc = Join-Path $projectRoot "web\vercel.json"
$vercelDst = Join-Path $buildWeb "vercel.json"
if (Test-Path $vercelSrc) {
    Copy-Item -Force $vercelSrc $vercelDst
}

# Vercel serverless API routes (proxy for Edge Functions — avoids Safari CORS)
$apiSrc = Join-Path $projectRoot "web\api"
$apiDst = Join-Path $buildWeb "api"
if (Test-Path $apiSrc) {
    if (-not (Test-Path $apiDst)) { New-Item -ItemType Directory -Path $apiDst | Out-Null }
    Copy-Item -Force -Recurse "$apiSrc\*" $apiDst
    Write-Host "Copied api/ serverless functions" -ForegroundColor Gray
}

if (-not (Test-Path $buildWeb)) {
    Write-Host "Build failed: build/web not found" -ForegroundColor Red
    exit 1
}

Write-Host "Deploying to Vercel..." -ForegroundColor Cyan
Set-Location $buildWeb
$scope = if ($env:VERCEL_SCOPE) { $env:VERCEL_SCOPE } else { "mannbillywes-projects" }
if ($env:VERCEL_TOKEN) {
    npx vercel deploy --prod --yes --scope $scope --token $env:VERCEL_TOKEN
} else {
    npx vercel deploy --prod --yes --scope $scope
}
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host "Deployment complete!" -ForegroundColor Green
