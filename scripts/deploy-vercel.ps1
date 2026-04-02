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
# --pwa-strategy=none: avoid service worker serving stale JS (old Edge function names / broken scan on iOS).
& flutter build web --release --pwa-strategy=none
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

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
