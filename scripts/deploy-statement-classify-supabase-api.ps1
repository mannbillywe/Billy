# Deploy the `statement-classify` Edge Function via Supabase Management API.
#
# Why this script exists:
# - Personal access tokens shaped like `sbp_v0_...` work with api.supabase.com but the
#   Supabase CLI may reject them ("Invalid access token format"). This uses the same
#   multipart upload the CLI sends: metadata JSON + one `file` part per source path.
#
# Prerequisites:
# - curl.exe (Windows 10+)
# - SUPABASE_ACCESS_TOKEN in environment, or in repo-root `.env.local` as:
#     SUPABASE_ACCESS_TOKEN=your_token
#
# Optional: `supabase/.temp/project-ref` (from `supabase link`) overrides default ref below.

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

$metaPath = Join-Path $env:TEMP "billy-statement-classify-deploy-metadata.json"
@'
{"entrypoint_path":"supabase/functions/statement-classify/index.ts","name":"statement-classify","verify_jwt":true}
'@ | Set-Content -Path $metaPath -Encoding utf8 -NoNewline

$indexTs = Join-Path $projectRoot "supabase\functions\statement-classify\index.ts"
$corsTs = Join-Path $projectRoot "supabase\functions\_shared\cors.ts"
$geminiTs = Join-Path $projectRoot "supabase\functions\_shared\resolve_gemini_key.ts"
foreach ($p in @($indexTs, $corsTs, $geminiTs)) {
    if (-not (Test-Path $p)) {
        Write-Host "Missing file: $p" -ForegroundColor Red
        exit 1
    }
}

Write-Host "Deploying statement-classify to project $projectRef ..." -ForegroundColor Cyan
$url = "https://api.supabase.com/v1/projects/$projectRef/functions/deploy?slug=statement-classify"
$args = @(
    "-s", "-S", "-f", "-w", "`nHTTP:%{http_code}",
    "-X", "POST", $url,
    "-H", "Authorization: Bearer $token",
    "-F", "metadata=@$metaPath;type=application/json",
    "-F", "file=@$indexTs;filename=supabase/functions/statement-classify/index.ts",
    "-F", "file=@$corsTs;filename=supabase/functions/_shared/cors.ts",
    "-F", "file=@$geminiTs;filename=supabase/functions/_shared/resolve_gemini_key.ts"
)
$output = & curl.exe @args 2>&1
Write-Host ($output | Out-String)
if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
}
Write-Host "Done. Dashboard: https://supabase.com/dashboard/project/$projectRef/functions" -ForegroundColor Green
