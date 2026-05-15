param(
    [string]$ProjectName = "Unreal Project",
    [string]$GitRepoPath = "",
    [string]$LogPath = "$env:LOCALAPPDATA\UnrealBuildTool\Log.txt",
    [int]$Port = 4173,
    [switch]$OpenBrowser,
    [switch]$EnableWindowsToast,
    [switch]$EnableSound
)

$ErrorActionPreference = "Stop"
$root = $PSScriptRoot
$serveOut = Join-Path $root "serve.out.log"
$serveErr = Join-Path $root "serve.err.log"
$monitorOut = Join-Path $root "monitor.out.log"
$monitorErr = Join-Path $root "monitor.err.log"

function Start-HiddenPowerShell {
    param(
        [string]$Command,
        [string]$StdOut,
        [string]$StdErr
    )

    Start-Process `
        -FilePath "powershell.exe" `
        -ArgumentList @("-NoProfile", "-ExecutionPolicy", "Bypass", "-Command", $Command) `
        -WorkingDirectory $root `
        -WindowStyle Hidden `
        -RedirectStandardOutput $StdOut `
        -RedirectStandardError $StdErr `
        -PassThru
}

$existingServer = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue
if (!$existingServer) {
    $serveScript = Join-Path $root "serve.ps1"
    Start-HiddenPowerShell -Command "& '$serveScript' -Port $Port" -StdOut $serveOut -StdErr $serveErr | Out-Null
}

# Kill any existing monitor.ps1 processes to prevent file lock conflicts
Get-WmiObject Win32_Process | Where-Object { $_.CommandLine -match "monitor\.ps1" } | ForEach-Object {
    Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue
}

$monitorScript = Join-Path $root "monitor.ps1"
$monitorCommand = "& '$monitorScript' -ProjectName '$ProjectName' -LogPath '$LogPath' -PollSeconds 1"
if ($GitRepoPath) {
    $monitorCommand += " -GitRepoPath '$GitRepoPath'"
}
if ($EnableWindowsToast) {
    $monitorCommand += " -EnableWindowsToast"
}
if ($EnableSound) {
    $monitorCommand += " -EnableSound"
}

Start-HiddenPowerShell -Command $monitorCommand -StdOut $monitorOut -StdErr $monitorErr | Out-Null

$url = "http://localhost:$Port"
if ($OpenBrowser) {
    Start-Process $url
}

[pscustomobject]@{
    Dashboard = $url
    ServeLog = $serveOut
    ServeErrorLog = $serveErr
    MonitorLog = $monitorOut
    MonitorErrorLog = $monitorErr
}
