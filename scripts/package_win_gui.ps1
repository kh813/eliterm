$ErrorActionPreference = "Stop"

Write-Host "Building Windows GUI application..."
$env:MIX_ENV="prod"

# Build the release
mix release eliterm --overwrite

$BuildDir = "_build\prod\rel\eliterm"
$DistDir = "Eliterm-Windows"

If (Test-Path $DistDir) { Remove-Item -Recurse -Force $DistDir }
New-Item -ItemType Directory -Force -Path $DistDir

# Copy the release contents
Copy-Item -Recurse -Force "$BuildDir\*" "$DistDir\"

# Create a small C# launcher to start the .bat hidden
$Source = @"
using System.Diagnostics;
class Program {
    static void Main(string[] args) {
        ProcessStartInfo info = new ProcessStartInfo();
        info.FileName = "bin\\eliterm.bat";
        info.Arguments = "start";
        info.CreateNoWindow = true;
        info.UseShellExecute = false;
        Process.Start(info);
    }
}
"@
Set-Content -Path "Launcher.cs" -Value $Source

$csc = (Get-ChildItem -Path "C:\Windows\Microsoft.NET\Framework64" -Filter "csc.exe" -Recurse | Sort-Object LastWriteTime -Descending)[0].FullName
& $csc /out:"$DistDir\Eliterm.exe" /target:winexe Launcher.cs
Remove-Item -Force "Launcher.cs"

Write-Host "Windows distribution prepared at $DistDir"
