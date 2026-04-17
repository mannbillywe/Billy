# Opens live-tail windows for every Billy / Goat Mode log stream on the dev box.
# Run from the repo root:   .\scripts\tail-logs.ps1
#
# Streams opened (each in its own window so you can watch them side-by-side):
#   1) Docker container        : FastAPI /health and /goat-mode/run hits + Python tracebacks
#   2) Cloudflared tunnel      : request routing, tunnel up/down, connection index
#   3) Vercel Function logs    : proxy invocations, upstream_status, duration_ms
#   4) Supabase Edge Function  : goat-mode-trigger function logs (requires SUPABASE_ACCESS_TOKEN)
#
# Nothing in here is destructive — all commands are tails. Close any window
# with Ctrl+C to stop that specific stream.

$ErrorActionPreference = "Stop"
$repo = (Resolve-Path ".").Path
$tunLog = Join-Path $repo ".tools\cloudflared-docker.err.log"
$supabaseCli = Join-Path $repo "node_modules\.bin\supabase.cmd"
$vercelRef = Join-Path $repo "build\web"

function Start-TailWindow {
    param([string]$title,[string]$command)
    $full = "`$Host.UI.RawUI.WindowTitle = '$title'; $command"
    Start-Process powershell.exe -ArgumentList @("-NoExit","-Command",$full) -WorkingDirectory $repo
}

Write-Host "Billy dev logs — opening tail windows"
Write-Host "repo      = $repo"

Write-Host "[1/4] Docker container (billy-ai-local)"
Start-TailWindow "billy: docker logs" "docker logs -f billy-ai-local"

Write-Host "[2/4] Cloudflared tunnel"
if (Test-Path $tunLog) {
    Start-TailWindow "billy: cloudflared" "Get-Content -Path '$tunLog' -Wait -Tail 30"
} else {
    Write-Host "   (no tunnel log at $tunLog — start cloudflared first)"
}

Write-Host "[3/4] Vercel prod Function logs"
Start-TailWindow "billy: vercel logs" "Set-Location '$vercelRef'; npm exec --yes --package=vercel@latest -- vercel logs --follow"

Write-Host "[4/4] Supabase Edge Function logs (goat-mode-trigger)"
if ($env:SUPABASE_ACCESS_TOKEN) {
    Start-TailWindow "billy: supabase fn logs" "& '$supabaseCli' functions logs goat-mode-trigger --project-ref wpzopkigbbldcfpxuvcm --tail"
} else {
    Write-Host "   (skipped — set `$env:SUPABASE_ACCESS_TOKEN first, or run 'supabase login' in node_modules/.bin)"
}

Write-Host ""
Write-Host "All configured streams opened. Close individual windows with Ctrl+C."
