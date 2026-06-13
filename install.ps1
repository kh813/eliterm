$ErrorActionPreference = "Stop"

Write-Host "Downloading Windows sleep watcher..."
$binDir = "$HOME\.local\bin"
if (-not (Test-Path -Path $binDir)) {
    New-Item -ItemType Directory -Force -Path $binDir | Out-Null
}

$url = "https://github.com/kh813/eliterm/releases/latest/download/win_sleep_watcher.exe"
$dest = "$binDir\eliterm_sleep_watcher.exe"
try {
    Invoke-WebRequest -Uri $url -OutFile $dest
    Write-Host "Sleep watcher downloaded successfully."
} catch {
    Write-Host "Failed to download sleep watcher. Are you sure a release exists on GitHub?"
}

Write-Host "Installing Eliterm..."
mix deps.get
mix compile
mix escript.build

Write-Host "Installation complete! The eliterm executable is in bin/eliterm."
