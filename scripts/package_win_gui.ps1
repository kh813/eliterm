$ErrorActionPreference = "Stop"

Write-Output "Building Windows GUI application..."
$env:MIX_ENV="prod"

# Compile sleep watcher to priv/ so it gets bundled into the release
$csc = (Get-ChildItem -Path "C:\Windows\Microsoft.NET\Framework64" -Filter "csc.exe" -Recurse | Sort-Object LastWriteTime -Descending)[0].FullName
& $csc /out:priv\eliterm_sleep_watcher.exe priv\win_sleep_watcher.cs

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
using System.IO;
using System.Reflection;

class Program {
    static void Main(string[] args) {
        string exeDir = Path.GetDirectoryName(Assembly.GetExecutingAssembly().Location);
        ProcessStartInfo info = new ProcessStartInfo();
        info.WorkingDirectory = exeDir;
        info.EnvironmentVariables["__COMPAT_LAYER"] = "HighDpiAware";
        info.FileName = "cmd.exe";
        info.Arguments = "/c bin\\eliterm.bat start > boot.log 2>&1";
        info.CreateNoWindow = true;
        info.UseShellExecute = false;
        Process.Start(info);
    }
}
"@
Set-Content -Path "Launcher.cs" -Value $Source

$csc = (Get-ChildItem -Path "C:\Windows\Microsoft.NET\Framework64" -Filter "csc.exe" -Recurse | Sort-Object LastWriteTime -Descending)[0].FullName
& $csc /out:"$DistDir\Eliterm.exe" /target:winexe /win32icon:"priv\icon.ico" Launcher.cs
Remove-Item -Force "Launcher.cs"

Write-Host "Windows distribution prepared at $DistDir"
