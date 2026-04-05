<#
.SYNOPSIS
  Shows the next Billy production-readiness step and a copy-paste prompt for Cursor.

.DESCRIPTION
  Progress is stored in scripts/.billy-cursor-step (gitignored). Run without flags to see
  the current step. Use -Complete after you finish the step in Cursor to advance.

.PARAMETER Complete
  Advance to the next step after printing the one you just finished.

.PARAMETER Reset
  Start over from step 0.

.PARAMETER List
  Print all step titles and ids.

.PARAMETER Jump
  Set current step index (0-based).

.EXAMPLE
  .\scripts\next-billy-step.ps1
.EXAMPLE
  .\scripts\next-billy-step.ps1 -Complete
#>
[CmdletBinding()]
param(
  [switch] $Complete,
  [switch] $Reset,
  [switch] $List,
  [int] $Jump = -1
)

$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RoadmapPath = Join-Path $ScriptDir "billy-cursor-roadmap.json"
$StatePath = Join-Path $ScriptDir ".billy-cursor-step"

if (-not (Test-Path $RoadmapPath)) {
  Write-Error "Missing roadmap: $RoadmapPath"
}

$raw = Get-Content -LiteralPath $RoadmapPath -Raw -Encoding UTF8
$data = $raw | ConvertFrom-Json
$steps = @($data.steps)
$vercelNote = $data.vercelNote

if ($List) {
  for ($i = 0; $i -lt $steps.Count; $i++) {
    Write-Host ("[{0}] {1} - {2}" -f $i, $steps[$i].id, $steps[$i].title)
  }
  exit 0
}

if ($Reset) {
  [System.IO.File]::WriteAllText($StatePath, "0")
  Write-Host "Reset to step 0."
}

if ($Jump -ge 0) {
  if ($Jump -ge $steps.Count) {
    Write-Error "Jump index $Jump is out of range (0..$($steps.Count - 1))."
  }
  [System.IO.File]::WriteAllText($StatePath, "$Jump")
  Write-Host "Jumped to step $Jump."
}

$idx = 0
if (Test-Path $StatePath) {
  $idx = [int]((Get-Content -LiteralPath $StatePath -Raw).Trim())
}

if ($idx -lt 0) { $idx = 0 }
if ($idx -ge $steps.Count) {
  Write-Host "All roadmap steps are complete. Only manual App Store / Play upload remains."
  Write-Host ""
  Write-Host "Vercel: $vercelNote"
  exit 0
}

$s = $steps[$idx]

Write-Host ""
Write-Host "========== Billy roadmap step $idx / $($steps.Count - 1) ==========" -ForegroundColor Cyan
Write-Host "id:    $($s.id)" -ForegroundColor DarkGray
Write-Host "title: $($s.title)"
Write-Host ""
Write-Host "--- Do this outside Cursor ---" -ForegroundColor Yellow
Write-Host $s.humanAction
Write-Host ""
Write-Host "--- Paste into Cursor (new chat or continue) ---" -ForegroundColor Green
Write-Host $s.cursorPrompt
Write-Host ""
Write-Host "Vercel note: $vercelNote" -ForegroundColor DarkGray
Write-Host "Doc: docs/PRODUCTION_READINESS.md"
Write-Host ""
Write-Host "When this step is done, run: .\scripts\next-billy-step.ps1 -Complete"
Write-Host ""

if ($Complete) {
  $next = $idx + 1
  if ($next -ge $steps.Count) {
    [System.IO.File]::WriteAllText($StatePath, "$next")
    Write-Host "Marked complete. Next run: you are past the last guided step (store upload is manual)." -ForegroundColor Cyan
  }
  else {
    [System.IO.File]::WriteAllText($StatePath, "$next")
    Write-Host "Advanced to step $next. Run again without -Complete to see the next prompt." -ForegroundColor Cyan
  }
}
elseif (-not $Reset -and $Jump -lt 0) {
  if (-not (Test-Path $StatePath)) {
    [System.IO.File]::WriteAllText($StatePath, "0")
  }
}
