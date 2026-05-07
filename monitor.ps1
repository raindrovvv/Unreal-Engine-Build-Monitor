param(
    [string]$LogPath = "$env:LOCALAPPDATA\UnrealBuildTool\Log.txt",
    [string]$StatusJsPath = (Join-Path $PSScriptRoot "build_status.js"),
    [string]$StatusJsonPath = (Join-Path $PSScriptRoot "build_status.json"),
    [int]$PollSeconds = 1,
    [switch]$NoJson
)

$ErrorActionPreference = "Stop"

function New-BuildStatus {
    param(
        [string]$Status,
        [string]$CurrentFile,
        [int]$CurrentAction,
        [int]$TotalActions,
        [double]$Progress,
        [string]$ElapsedTime
    )

    [ordered]@{
        total_actions = $TotalActions
        current_action = $CurrentAction
        current_file = $CurrentFile
        progress = $Progress
        status = $Status
        elapsed_time = $ElapsedTime
        last_update = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
    }
}

function Write-BuildStatus {
    param([System.Collections.IDictionary]$StatusData)

    $statusDir = Split-Path $StatusJsPath
    if ($statusDir -and !(Test-Path $statusDir)) {
        New-Item -ItemType Directory -Path $statusDir -Force | Out-Null
    }

    $json = $StatusData | ConvertTo-Json -Depth 3
    "window.buildStatus = $json;" | Out-File -FilePath $StatusJsPath -Encoding utf8 -Force

    if (!$NoJson) {
        $jsonDir = Split-Path $StatusJsonPath
        if ($jsonDir -and !(Test-Path $jsonDir)) {
            New-Item -ItemType Directory -Path $jsonDir -Force | Out-Null
        }
        $json | Out-File -FilePath $StatusJsonPath -Encoding utf8 -Force
    }
}

function Get-BuildStatusFromLog {
    param(
        [string[]]$Lines,
        [timespan]$Elapsed
    )

    $totalActions = 0
    $currentAction = 0
    $currentFile = "Waiting for build step..."
    $status = "RUNNING"

    foreach ($line in $Lines) {
        if ($line -match "Using Parallel executor to run (\d+) action\(s\)") {
            $totalActions = [int]$Matches[1]
        }

        if ($line -match "\[(\d+)/(\d+)\]\s+(Compile|Link|Resource|WriteMetadata|GenerateHeader|Copy|Action)\s+(?:\[[^\]]+\]\s+)?(.+)") {
            $currentAction = [int]$Matches[1]
            $totalActions = [int]$Matches[2]
            $currentFile = $Matches[4]
        }

        if ($line -match "Result:\s*Succeeded|BUILD SUCCESSFUL|Build succeeded") {
            $status = "SUCCEEDED"
            $currentFile = "Build complete."
        }

        if ($line -match "Result:\s*Failed|BUILD FAILED|Build Failed|error MSB\d+") {
            $status = "FAILED"
            $currentFile = "Build failed. Check the Unreal Build Tool log."
        }
    }

    if ($totalActions -lt 1) {
        $totalActions = 0
        $currentAction = 0
        $progress = 0
    } else {
        if ($currentAction -gt $totalActions) {
            $currentAction = $totalActions
        }
        $progress = [Math]::Round(($currentAction / $totalActions) * 100, 1)
    }

    if ($status -eq "SUCCEEDED") {
        $progress = 100
        if ($totalActions -gt 0) {
            $currentAction = $totalActions
        }
    }

    New-BuildStatus `
        -Status $status `
        -CurrentFile $currentFile `
        -CurrentAction $currentAction `
        -TotalActions $totalActions `
        -Progress $progress `
        -ElapsedTime ("{0:hh\:mm\:ss}" -f $Elapsed)
}

if ($PollSeconds -lt 1) {
    throw "PollSeconds must be 1 or greater."
}

Write-Host "Monitoring Unreal Build Tool log:" -ForegroundColor Cyan
Write-Host "  Log:    $LogPath"
Write-Host "  Output: $StatusJsPath"
if (!$NoJson) {
    Write-Host "  JSON:   $StatusJsonPath"
}
Write-Host "Press Ctrl+C to stop." -ForegroundColor DarkGray

$startTime = [DateTime]::Now

while ($true) {
    $elapsed = [DateTime]::Now - $startTime

    if (Test-Path $LogPath) {
        $lines = Get-Content $LogPath -Tail 300 -ErrorAction SilentlyContinue
        $statusData = Get-BuildStatusFromLog -Lines $lines -Elapsed $elapsed
    } else {
        $statusData = New-BuildStatus `
            -Status "WAITING" `
            -CurrentFile "Waiting for log file: $LogPath" `
            -CurrentAction 0 `
            -TotalActions 0 `
            -Progress 0 `
            -ElapsedTime ("{0:hh\:mm\:ss}" -f $elapsed)
    }

    Write-BuildStatus -StatusData $statusData
    Start-Sleep -Seconds $PollSeconds
}
