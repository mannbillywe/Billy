# Install useful skills from awesome-agent-skills into .cursor/skills/
# Run from project root: .\scripts\install-skills.ps1

$skillsDir = Join-Path (Join-Path $PSScriptRoot "..") ".cursor\skills"
$tempDir = Join-Path $env:TEMP "awesome-agent-skills"

Write-Host "Installing skills to $skillsDir" -ForegroundColor Cyan

# Clone or update awesome-agent-skills
if (Test-Path $tempDir) {
    Push-Location $tempDir
    git pull
    Pop-Location
} else {
    git clone --depth 1 https://github.com/VoltAgent/awesome-agent-skills.git $tempDir
}

# Skills to install - clone from GitHub
$skills = @(
    @{
        name = "supabase-postgres-best-practices"
        repo = "supabase/agent-skills"
        path = "skills/supabase-postgres-best-practices"
    },
    @{
        name = "gemini-api-dev"
        repo = "google-gemini/gemini-skills"
        path = "skills/gemini-api-dev"
    }
)

foreach ($skill in $skills) {
    $dest = Join-Path $skillsDir $skill.name
    if (Test-Path $dest) {
        Write-Host "  $($skill.name) already installed" -ForegroundColor Yellow
        continue
    }
    
    $repoName = $skill.repo -replace ".*/", ""
    $clonePath = Join-Path $env:TEMP $repoName
    if (-not (Test-Path $clonePath)) {
        git clone --depth 1 "https://github.com/$($skill.repo).git" $clonePath
    }
    
    $srcPath = if ($skill.path) { Join-Path $clonePath $skill.path } else { $clonePath }
    if (Test-Path $srcPath) {
        Copy-Item -Path $srcPath -Destination $dest -Recurse -Force
        Write-Host "  Installed $($skill.name)" -ForegroundColor Green
    } else {
        Write-Host "  Skipped $($skill.name) - path not found" -ForegroundColor Red
    }
}

Write-Host "`nDone. Restart Cursor to pick up new skills." -ForegroundColor Cyan
