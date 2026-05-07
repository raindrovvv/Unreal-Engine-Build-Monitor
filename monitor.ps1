# PowerShell Background Monitor for Unreal Build Tool Logs (JS-based to bypass CORS)
$logPath = "$env:LOCALAPPDATA\UnrealBuildTool\Log.txt"
$statusJsPath = Join-Path $PSScriptRoot "build_status.js"

# Ensure the parent directory exists
$dir = Split-Path $statusJsPath
if (!(Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force }

Write-Host "Monitoring started on log file: $logPath" -ForegroundColor Cyan

$startTime = [DateTime]::Now

while ($true) {
    if (Test-Path $logPath) {
        # Read the tail end of the log to capture active compiles
        $lines = Get-Content $logPath -Tail 200 -ErrorAction SilentlyContinue
        
        $totalActions = 1
        $currentAction = 0
        $currentFile = "Initializing..."
        $status = "RUNNING"
        
        # Parse total actions
        foreach ($line in $lines) {
            if ($line -match "Using Parallel executor to run (\d+) action\(s\)") {
                $totalActions = [int]$Matches[1]
            }
            # Parse progress: [45/187] Compile [x64] FileName.cpp
            if ($line -match "\[(\d+)/(\d+)\]\s+(Compile|Link)\s+\[x64\]\s+(.+)") {
                $currentAction = [int]$Matches[1]
                $totalActions = [int]$Matches[2]
                $currentFile = $Matches[4]
            }
            if ($line -match "Result: Succeeded") {
                $status = "SUCCEEDED"
                $currentFile = "Build complete! Launching Unreal Editor..."
            }
            if ($line -match "Result: Failed" -or $line -match "Build Failed") {
                $status = "FAILED"
                $currentFile = "Compilation failed. Check error logs."
            }
        }
        
        $elapsed = [DateTime]::Now - $startTime
        $elapsedStr = "{0:mm\:ss}" -f $elapsed
        
        if ($currentAction -gt $totalActions) { $currentAction = $totalActions }
        $progress = [Math]::Round(($currentAction / $totalActions) * 100, 1)
        if ($status -eq "SUCCEEDED") { $progress = 100.0 }
        
        # Clean currentFile for JS safety
        $safeFile = $currentFile.Replace("\", "\\").Replace("'", "\'")
        
        # Prepare status payload as JS variable
        $statusJs = "window.buildStatus = {
    `"total_actions`": $totalActions,
    `"current_action`": $currentAction,
    `"current_file`": `"$safeFile`",
    `"progress`": $progress,
    `"status`": `"$status`",
    `"elapsed_time`": `"$elapsedStr`",
    `"last_update`": `"$((Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))`"
};"
        
        $statusJs | Out-File -FilePath $statusJsPath -Encoding utf8 -Force
    }
    Start-Sleep -Seconds 1
}
