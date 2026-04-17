<#
.SYNOPSIS
  Local Goat Mode runner for Windows PowerShell.

.DESCRIPTION
  Avoids the `curl` alias / heredoc quoting problems of Invoke-WebRequest.
  Uses Invoke-RestMethod and returns parsed JSON so you can pipe into
  ConvertTo-Json or inspect properties directly.

.EXAMPLES
  # Dry-run (no DB writes) for the UUID in $env:GOAT_TEST_USER_ID or .env
  ./scripts/goat/run-local.ps1 -DryRun

  # Wet-run for a specific user and scope, print the short summary
  ./scripts/goat/run-local.ps1 -UserId 3d8238ac-97bd-49e5-9ee7-1966447bae7c -Scope full

  # Fetch the latest snapshot for a scope
  ./scripts/goat/run-local.ps1 -Latest -UserId 3d8238ac-97bd-49e5-9ee7-1966447bae7c -Scope overview
#>

[CmdletBinding()]
param(
    [string]$BaseUrl = 'http://localhost:8080',
    [string]$UserId,
    [ValidateSet('overview','cashflow','budgets','recurring','debt','goals','full')]
    [string]$Scope = 'full',
    [switch]$DryRun,
    [switch]$Latest,
    [string]$JobId,
    [string]$RangeStart,
    [string]$RangeEnd
)

$ErrorActionPreference = 'Stop'

function Read-DotEnv {
    param([string]$Path)
    if (-not (Test-Path $Path)) { return @{} }
    $map = @{}
    foreach ($line in Get-Content $Path) {
        if ($line -match '^\s*#') { continue }
        if ($line -match '^\s*([A-Z_][A-Z0-9_]*)\s*=\s*(.*)\s*$') {
            $map[$matches[1]] = $matches[2]
        }
    }
    return $map
}

# Resolve UserId from param → env → .env fallback.
if (-not $UserId) {
    if ($env:GOAT_TEST_USER_ID) {
        $UserId = $env:GOAT_TEST_USER_ID
    } else {
        $env = Read-DotEnv (Join-Path $PSScriptRoot '..\..\backend\app\.env')
        if ($env.ContainsKey('GOAT_TEST_USER_ID')) { $UserId = $env['GOAT_TEST_USER_ID'] }
    }
}

if ($JobId) {
    Invoke-RestMethod -Method Get -Uri "$BaseUrl/goat-mode/jobs/$JobId" | ConvertTo-Json -Depth 12
    return
}

if ($Latest) {
    if (-not $UserId) { throw 'UserId required for -Latest' }
    Invoke-RestMethod -Method Get -Uri "$BaseUrl/goat-mode/latest/$UserId`?scope=$Scope" | ConvertTo-Json -Depth 12
    return
}

if (-not $UserId) { throw 'UserId required. Pass -UserId or set GOAT_TEST_USER_ID in .env' }

$body = @{
    user_id = $UserId
    scope   = $Scope
    dry_run = [bool]$DryRun
}
if ($RangeStart) { $body.range_start = $RangeStart }
if ($RangeEnd)   { $body.range_end   = $RangeEnd }

$json = $body | ConvertTo-Json -Compress
Write-Host "POST $BaseUrl/goat-mode/run  $json" -ForegroundColor Cyan
$resp = Invoke-RestMethod -Method Post -Uri "$BaseUrl/goat-mode/run" -ContentType 'application/json' -Body $json
$resp | ConvertTo-Json -Depth 12
