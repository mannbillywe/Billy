# Deploy `goat-setup-chat` Edge Function via Supabase Management API.
# Same multipart pattern as deploy-statement-classify-supabase-api.ps1 (sbp_v0_ tokens).
#
# Prerequisites:
# - curl.exe (Windows 10+)
# - SUPABASE_ACCESS_TOKEN in environment, or repo-root `.env.local`:
#     SUPABASE_ACCESS_TOKEN=your_token

$ErrorActionPreference = "Stop"
$projectRoot = Split-Path -Parent $PSScriptRoot
Set-Location $projectRoot

$token = $env:SUPABASE_ACCESS_TOKEN
if (-not $token) {
    $envLocal = Join-Path $projectRoot ".env.local"
    if (Test-Path $envLocal) {
        foreach ($line in Get-Content $envLocal) {
            if ($line -match '^\s*SUPABASE_ACCESS_TOKEN=(.+)$') {
                $token = $Matches[1].Trim().Trim('"')
                break
            }
        }
    }
}
if (-not $token) {
    Write-Host "Set SUPABASE_ACCESS_TOKEN or add it to .env.local (gitignored)." -ForegroundColor Red
    exit 1
}

$refPath = Join-Path $projectRoot "supabase\.temp\project-ref"
$projectRef = "wpzopkigbbldcfpxuvcm"
if (Test-Path $refPath) {
    $fromFile = (Get-Content $refPath -Raw).Trim()
    if ($fromFile.Length -gt 0) { $projectRef = $fromFile }
}

$metaPath = Join-Path $env:TEMP "billy-goat-setup-chat-deploy-metadata.json"
# BOM breaks Supabase API ("expected value at line 1 column 1") — write UTF-8 without BOM.
$metaJson = '{"entrypoint_path":"supabase/functions/goat-setup-chat/index.ts","name":"goat-setup-chat","verify_jwt":true}'
[System.IO.File]::WriteAllText($metaPath, $metaJson, [System.Text.UTF8Encoding]::new($false))

$indexTs = Join-Path $projectRoot "supabase\functions\goat-setup-chat\index.ts"
$corsTs = Join-Path $projectRoot "supabase\functions\_shared\cors.ts"
$geminiTs = Join-Path $projectRoot "supabase\functions\_shared\resolve_gemini_key.ts"
foreach ($p in @($indexTs, $corsTs, $geminiTs)) {
    if (-not (Test-Path $p)) {
        Write-Host "Missing file: $p" -ForegroundColor Red
        exit 1
    }
}

Write-Host "Deploying goat-setup-chat to project $projectRef ..." -ForegroundColor Cyan
$url = "https://api.supabase.com/v1/projects/$projectRef/functions/deploy?slug=goat-setup-chat"
$curlArgs = @(
    "-s", "-S", "-f", "-w", "`nHTTP:%{http_code}",
    "-X", "POST", $url,
    "-H", "Authorization: Bearer $token",
    "-F", "metadata=@$metaPath;type=application/json",
    "-F", "file=@$indexTs;filename=supabase/functions/goat-setup-chat/index.ts",
    "-F", "file=@$corsTs;filename=supabase/functions/_shared/cors.ts",
    "-F", "file=@$geminiTs;filename=supabase/functions/_shared/resolve_gemini_key.ts"
)
$output = & curl.exe @curlArgs 2>&1
Write-Host ($output | Out-String)
if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
}
Write-Host "Done. Dashboard: https://supabase.com/dashboard/project/$projectRef/functions" -ForegroundColor Green
