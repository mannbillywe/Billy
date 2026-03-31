# Deploy Billy Flutter web app to Vercel
# Prerequisites: Flutter SDK, Vercel CLI (npm i -g vercel)
# Set VERCEL_TOKEN env var with your token, or run: vercel login

$ErrorActionPreference = "Stop"
$projectRoot = Split-Path -Parent $PSScriptRoot
$buildWeb = Join-Path $projectRoot "build\web"

Write-Host "Building Flutter web..." -ForegroundColor Cyan
Set-Location $projectRoot
& "C:\Users\mannt\AppData\Local\flutter\bin\flutter.bat" build web --release
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

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
