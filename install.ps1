$ErrorActionPreference = "Stop"

Write-Host "Compiling Windows sleep watcher..."
$cscPaths = Get-ChildItem -Path "C:\Windows\Microsoft.NET\Framework64" -Filter "csc.exe" -Recurse -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending
if ($cscPaths.Count -gt 0) {
    $csc = $cscPaths[0].FullName
    $binDir = "$HOME\.local\bin"
    if (-not (Test-Path -Path $binDir)) {
        New-Item -ItemType Directory -Force -Path $binDir | Out-Null
    }
    
    & $csc /out:"$binDir\eliterm_sleep_watcher.exe" "priv\win_sleep_watcher.cs"
    if ($LASTEXITCODE -eq 0) {
        Write-Host "Sleep watcher compiled successfully."
    } else {
        Write-Host "Failed to compile sleep watcher."
    }
} else {
    Write-Host "csc.exe not found. Please ensure .NET Framework is installed."
}

Write-Host "Installing Eliterm..."
mix deps.get
mix compile
mix escript.build

Write-Host "Installation complete! The eliterm executable is in bin/eliterm."
