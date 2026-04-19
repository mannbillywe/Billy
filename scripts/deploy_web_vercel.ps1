<#
    deploy_web_vercel.ps1
    ---------------------
    Builds Flutter web (release) and deploys the `build/web` folder to Vercel.

    Prereqs:
      * Node.js + npm (for `npx vercel`)
      * `vercel login` once on this machine (or set VERCEL_TOKEN)
      * Flutter on PATH

    Optional env vars for Supabase at build time (same as GitHub Actions):
      $env:SUPABASE_URL = 'https://xxx.supabase.co'
      $env:SUPABASE_ANON_KEY = 'eyJ...'

    Usage (from repo root):
      .\scripts\deploy_web_vercel.ps1
      .\scripts\deploy_web_vercel.ps1 -SkipBuild
#>
[CmdletBinding()]
param(
    [switch]$SkipBuild
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
Set-Location $repoRoot

if (-not $SkipBuild) {
    Write-Host '[>] flutter pub get' -ForegroundColor Cyan
    flutter pub get
    if ($LASTEXITCODE -ne 0) { throw 'flutter pub get failed' }

    $url = $env:SUPABASE_URL
    $anon = $env:SUPABASE_ANON_KEY
    if ($url -and $anon) {
        Write-Host '[>] flutter build web (with SUPABASE_* env)' -ForegroundColor Cyan
        flutter build web --release --no-wasm-dry-run `
            "--dart-define=SUPABASE_URL=$url" `
            "--dart-define=SUPABASE_ANON_KEY=$anon"
    } else {
        Write-Host '[>] flutter build web (embedded Supabase fallback for web — see supabase_config.dart)' -ForegroundColor Cyan
        flutter build web --release --no-wasm-dry-run
    }
    if ($LASTEXITCODE -ne 0) { throw 'flutter build web failed' }
}

$webOut = Join-Path $repoRoot 'build\web'
if (-not (Test-Path (Join-Path $webOut 'index.html'))) {
    throw "Missing $webOut\index.html - run without -SkipBuild first."
}

Write-Host '[>] staging Vercel config + api/* into build\web' -ForegroundColor Cyan
Copy-Item (Join-Path $repoRoot 'web\vercel.json') (Join-Path $webOut 'vercel.json') -Force
$apiSrc = Join-Path $repoRoot 'web\api'
$apiDst = Join-Path $webOut 'api'
if (Test-Path $apiSrc) {
    New-Item -ItemType Directory -Force -Path $apiDst | Out-Null
    Copy-Item (Join-Path $apiSrc '*') $apiDst -Recurse -Force
}

Write-Host '[>] npx vercel deploy --prod (directory: build\web)' -ForegroundColor Cyan
Push-Location $webOut
try {
    npx --yes vercel deploy --prod --yes .
    if ($LASTEXITCODE -ne 0) { throw 'vercel deploy failed' }
} finally {
    Pop-Location
}
Write-Host '[v] Done.' -ForegroundColor Green
