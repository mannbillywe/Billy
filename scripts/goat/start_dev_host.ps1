# Start the Goat Mode "dev-host" pattern:
#   1. launch the local FastAPI backend on :8080
#   2. launch a Cloudflare Tunnel that gives it a public HTTPS URL
#   3. push that URL to the Supabase Edge Function secrets
#
# After this, the remote pipeline is live:
#   Flutter -> Supabase Edge Function -> Cloudflare Tunnel -> your PC -> Supabase
#
# Usage:
#   .\scripts\goat\start_dev_host.ps1
#
# Notes:
# - quick-mode Cloudflare tunnels get a NEW random URL on every restart, which
#   is why we push the URL to Supabase automatically each run.
# - Ctrl+C stops the tunnel; the backend keeps running in its own terminal.

$ErrorActionPreference = "Continue"
$projectRoot = Split-Path -Parent $PSScriptRoot | Split-Path -Parent
Set-Location $projectRoot

# ---- Read required config ----------------------------------------------------
function Get-EnvValue([string]$file, [string]$key) {
  if (-not (Test-Path $file)) { return $null }
  $line = (Get-Content $file | Where-Object { $_ -match "^\s*$([regex]::Escape($key))\s*=" } | Select-Object -First 1)
  if (-not $line) { return $null }
  return ($line -replace "^\s*$([regex]::Escape($key))\s*=\s*", "").Trim().Trim('"').Trim("'")
}

$sharedSecret = Get-EnvValue "backend\app\.env" "GOAT_BACKEND_SHARED_SECRET"
$supabaseAccessToken = Get-EnvValue ".env" "SUPABASE_ACCESS_TOKEN"
$projectRef = if ($env:SUPABASE_PROJECT_REF) { $env:SUPABASE_PROJECT_REF } else { "wpzopkigbbldcfpxuvcm" }

if (-not $sharedSecret) { throw "GOAT_BACKEND_SHARED_SECRET missing from backend/app/.env" }
if (-not $supabaseAccessToken) { throw "SUPABASE_ACCESS_TOKEN missing from .env" }
$env:SUPABASE_ACCESS_TOKEN = $supabaseAccessToken

$cloudflared = Join-Path $projectRoot ".tools\cloudflared.exe"
if (-not (Test-Path $cloudflared)) { throw "cloudflared.exe not found at .tools\cloudflared.exe" }

# ---- Free port 8080 ----------------------------------------------------------
$listener = Get-NetTCPConnection -LocalPort 8080 -State Listen -ErrorAction SilentlyContinue
if ($listener) {
  Write-Host "Stopping existing process on :8080 (PID $($listener.OwningProcess -join ','))"
  $listener.OwningProcess | Select-Object -Unique | ForEach-Object {
    Stop-Process -Id $_ -Force -ErrorAction SilentlyContinue
  }
  Start-Sleep -Seconds 2
}

# ---- Launch backend ----------------------------------------------------------
$logDir = Join-Path $projectRoot ".tools\logs"
if (-not (Test-Path $logDir)) { New-Item -Type Directory $logDir | Out-Null }
$backendLog = Join-Path $logDir "backend.log"
$tunnelLog  = Join-Path $logDir "cloudflared.log"

Write-Host "Launching backend -> $backendLog" -ForegroundColor Cyan
$backendArgs = @(
  "/c",
  "cd /d `"$projectRoot\backend\app`" && call .venv\Scripts\activate.bat && uvicorn main:app --host 127.0.0.1 --port 8080 > `"$backendLog`" 2>&1"
)
$backendProc = Start-Process cmd.exe -ArgumentList $backendArgs -WindowStyle Hidden -PassThru
Write-Host "  backend PID: $($backendProc.Id)"

Write-Host "Waiting for backend /health..." -ForegroundColor Cyan
$backendReady = $false
for ($i = 0; $i -lt 30; $i++) {
  Start-Sleep -Seconds 1
  try {
    $h = Invoke-RestMethod -Uri "http://127.0.0.1:8080/health" -TimeoutSec 2
    if ($h.ok) { $backendReady = $true; break }
  } catch {}
}
if (-not $backendReady) {
  Write-Host "Backend failed to come up. Check $backendLog" -ForegroundColor Red
  exit 1
}
Write-Host "  backend OK (ai_enabled=$($h.ai_enabled), shared_secret_required=$($h.shared_secret_required))" -ForegroundColor Green

# ---- Launch cloudflared -----------------------------------------------------
Write-Host "Launching Cloudflare quick tunnel -> $tunnelLog" -ForegroundColor Cyan
if (Test-Path $tunnelLog) { Remove-Item $tunnelLog -Force }
$tunnelProc = Start-Process $cloudflared `
  -ArgumentList @("tunnel","--url","http://127.0.0.1:8080","--no-autoupdate","--logfile",$tunnelLog,"--metrics","127.0.0.1:0") `
  -WindowStyle Hidden -PassThru
Write-Host "  cloudflared PID: $($tunnelProc.Id)"

Write-Host "Waiting for tunnel URL..." -ForegroundColor Cyan
$tunnelUrl = $null
for ($i = 0; $i -lt 45; $i++) {
  Start-Sleep -Seconds 1
  if (-not (Test-Path $tunnelLog)) { continue }
  $logText = Get-Content $tunnelLog -Raw -ErrorAction SilentlyContinue
  if ($logText -match 'https://[a-z0-9-]+\.trycloudflare\.com') {
    $tunnelUrl = $matches[0]
    break
  }
}
if (-not $tunnelUrl) {
  Write-Host "Could not find tunnel URL in $tunnelLog after 45s" -ForegroundColor Red
  Stop-Process -Id $tunnelProc.Id -Force -ErrorAction SilentlyContinue
  exit 1
}
Write-Host "  tunnel URL: $tunnelUrl" -ForegroundColor Green

# ---- Verify tunnel reaches backend ------------------------------------------
try {
  $remoteHealth = Invoke-RestMethod -Uri "$tunnelUrl/health" -TimeoutSec 15
  if (-not $remoteHealth.ok) { throw "unexpected /health payload" }
  Write-Host "  tunnel -> backend OK" -ForegroundColor Green
} catch {
  Write-Host "  tunnel -> backend FAILED: $($_.Exception.Message)" -ForegroundColor Red
  exit 1
}

# ---- Push tunnel URL to Supabase Edge Function secrets ----------------------
Write-Host "Pushing GOAT_BACKEND_URL to Supabase function secrets..." -ForegroundColor Cyan
$tmp = New-TemporaryFile
$tmpPath = $tmp.FullName
try {
  $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
  $content = "GOAT_BACKEND_URL=$tunnelUrl`nGOAT_BACKEND_SHARED_SECRET=$sharedSecret`n"
  [IO.File]::WriteAllText($tmpPath, $content, $utf8NoBom)
  npx --yes supabase@latest secrets set --project-ref $projectRef --env-file $tmpPath
  if ($LASTEXITCODE -ne 0) { throw "supabase secrets set failed" }
} finally {
  Remove-Item -Force -ErrorAction SilentlyContinue $tmpPath
}

# ---- Summary -----------------------------------------------------------------
Write-Host ""
Write-Host "=====================================================================" -ForegroundColor Green
Write-Host "  Goat Mode dev-host is LIVE" -ForegroundColor Green
Write-Host "=====================================================================" -ForegroundColor Green
Write-Host "  backend PID       : $($backendProc.Id)  (log: $backendLog)"
Write-Host "  cloudflared PID   : $($tunnelProc.Id)   (log: $tunnelLog)"
Write-Host "  tunnel URL        : $tunnelUrl"
Write-Host "  Edge Function URL : https://$projectRef.supabase.co/functions/v1/goat-mode-trigger"
Write-Host ""
Write-Host "To stop everything:" -ForegroundColor Yellow
Write-Host "  Stop-Process -Id $($backendProc.Id), $($tunnelProc.Id) -Force"
Write-Host ""
