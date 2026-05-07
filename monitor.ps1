param(
    [string]$LogPath = "$env:LOCALAPPDATA\UnrealBuildTool\Log.txt",
    [string]$StatusJsPath = (Join-Path $PSScriptRoot "build_status.js"),
    [string]$StatusJsonPath = (Join-Path $PSScriptRoot "build_status.json"),
    [string]$HistoryJsonPath = (Join-Path $PSScriptRoot "build_history.json"),
    [string]$ProjectName = "Unreal Project",
    [int]$PollSeconds = 1,
    [int]$HistoryLimit = 10,
    [int]$SlowFileLimit = 5,
    [switch]$NoJson,
    [switch]$NoHistory,
    [string]$WebhookUrl = ""
)

$ErrorActionPreference = "Stop"

$terminalStatuses = @("SUCCEEDED", "FAILED")
$history = @()
$slowFiles = @{}
$trackedFile = ""
$trackedFileStartedAt = $null
$lastRecordedStatus = ""
$lastNotificationKey = ""

function Read-History {
    if ($NoHistory -or !(Test-Path $HistoryJsonPath)) {
        return @()
    }

    try {
        $items = Get-Content $HistoryJsonPath -Raw | ConvertFrom-Json
        if ($null -eq $items) {
            return @()
        }
        return @($items)
    } catch {
        Write-Warning "Could not read history file: $HistoryJsonPath"
        return @()
    }
}

function Save-History {
    param([object[]]$Items)

    if ($NoHistory) {
        return
    }

    $historyDir = Split-Path $HistoryJsonPath
    if ($historyDir -and !(Test-Path $historyDir)) {
        New-Item -ItemType Directory -Path $historyDir -Force | Out-Null
    }

    $Items | ConvertTo-Json -Depth 6 | Out-File -FilePath $HistoryJsonPath -Encoding utf8 -Force
}

function New-BuildStatus {
    param(
        [string]$Status,
        [string]$Stage,
        [string]$CurrentFile,
        [int]$CurrentAction,
        [int]$TotalActions,
        [double]$Progress,
        [string]$ElapsedTime,
        [string]$FirstError,
        [string[]]$Errors
    )

    [ordered]@{
        project_name = $ProjectName
        total_actions = $TotalActions
        current_action = $CurrentAction
        current_file = $CurrentFile
        progress = $Progress
        status = $Status
        stage = $Stage
        elapsed_time = $ElapsedTime
        first_error = $FirstError
        errors = @($Errors)
        slow_files = Get-SlowFiles
        history = @($history)
        last_update = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
    }
}

function Get-SlowFiles {
    $slowFiles.GetEnumerator() |
        Sort-Object Value -Descending |
        Select-Object -First $SlowFileLimit |
        ForEach-Object {
            [ordered]@{
                file = $_.Key
                seconds = [Math]::Round([double]$_.Value, 1)
            }
        }
}

function Write-BuildStatus {
    param([System.Collections.IDictionary]$StatusData)

    $statusDir = Split-Path $StatusJsPath
    if ($statusDir -and !(Test-Path $statusDir)) {
        New-Item -ItemType Directory -Path $statusDir -Force | Out-Null
    }

    $json = $StatusData | ConvertTo-Json -Depth 8
    "window.buildStatus = $json;" | Out-File -FilePath $StatusJsPath -Encoding utf8 -Force

    if (!$NoJson) {
        $jsonDir = Split-Path $StatusJsonPath
        if ($jsonDir -and !(Test-Path $jsonDir)) {
            New-Item -ItemType Directory -Path $jsonDir -Force | Out-Null
        }
        $json | Out-File -FilePath $StatusJsonPath -Encoding utf8 -Force
    }
}

function Get-ErrorLines {
    param([string[]]$Lines)

    $patterns = @(
        "fatal error .+",
        "error\s+(?:C|LNK|MSB|CS)\d+:.+",
        "UHT Error:.+",
        "UnrealHeaderTool.+Error:.+",
        ":\s*error:.+",
        "BuildException:.+"
    )

    $foundErrors = New-Object System.Collections.Generic.List[string]
    foreach ($line in $Lines) {
        foreach ($pattern in $patterns) {
            if ($line -match $pattern) {
                $clean = $Matches[0].Trim()
                if (!$foundErrors.Contains($clean)) {
                    $foundErrors.Add($clean)
                }
                break
            }
        }
        if ($foundErrors.Count -ge 5) {
            break
        }
    }

    @($foundErrors)
}

function Get-BuildStatusFromLog {
    param(
        [string[]]$Lines,
        [timespan]$Elapsed
    )

    $totalActions = 0
    $currentAction = 0
    $currentFile = "Waiting for build step..."
    $stage = "Watching Log"
    $status = "RUNNING"

    foreach ($line in $Lines) {
        if ($line -match "UnrealHeaderTool|Parsing headers|Reflection code generated") {
            $stage = "Parsing Headers"
        }

        if ($line -match "Using Parallel executor to run (\d+) action\(s\)") {
            $totalActions = [int]$Matches[1]
            $stage = "Preparing Actions"
        }

        if ($line -match "\[(\d+)/(\d+)\]\s+(Compile|Link|Resource|WriteMetadata|GenerateHeader|Copy|Action)\s+(?:\[[^\]]+\]\s+)?(.+)") {
            $currentAction = [int]$Matches[1]
            $totalActions = [int]$Matches[2]
            $action = $Matches[3]
            $currentFile = $Matches[4]

            switch -Regex ($action) {
                "Compile" { $stage = "Compiling"; break }
                "Link" { $stage = "Linking"; break }
                "WriteMetadata|GenerateHeader" { $stage = "Writing Metadata"; break }
                "Resource|Copy" { $stage = "Copying Outputs"; break }
                default { $stage = "Running Actions" }
            }
        }

        if ($line -match "Result:\s*Succeeded|BUILD SUCCESSFUL|Build succeeded") {
            $status = "SUCCEEDED"
            $stage = "Succeeded"
            $currentFile = "Build complete."
        }

        if ($line -match "Result:\s*Failed|BUILD FAILED|Build Failed|error MSB\d+") {
            $status = "FAILED"
            $stage = "Failed"
            $currentFile = "Build failed. Check the Unreal Build Tool log."
        }
    }

    $errors = @(Get-ErrorLines -Lines $Lines)
    if ($errors.Count -gt 0) {
        $status = "FAILED"
        $stage = "Failed"
        $currentFile = "Build failed. Check the error summary."
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
        -Stage $stage `
        -CurrentFile $currentFile `
        -CurrentAction $currentAction `
        -TotalActions $totalActions `
        -Progress $progress `
        -ElapsedTime ("{0:hh\:mm\:ss}" -f $Elapsed) `
        -FirstError ($errors | Select-Object -First 1) `
        -Errors $errors
}

function Update-SlowFileTracking {
    param([System.Collections.IDictionary]$StatusData)

    $candidate = [string]$StatusData.current_file
    $status = [string]$StatusData.status
    $isTrackable = $status -eq "RUNNING" -and $candidate -and
        $candidate -notmatch "^Waiting|Build complete|Build failed"

    if (!$isTrackable) {
        return
    }

    if ($candidate -ne $script:trackedFile) {
        if ($script:trackedFile -and $script:trackedFileStartedAt) {
            $seconds = ([DateTime]::Now - $script:trackedFileStartedAt).TotalSeconds
            if ($script:slowFiles.ContainsKey($script:trackedFile)) {
                $script:slowFiles[$script:trackedFile] += $seconds
            } else {
                $script:slowFiles[$script:trackedFile] = $seconds
            }
        }

        $script:trackedFile = $candidate
        $script:trackedFileStartedAt = [DateTime]::Now
    }
}

function Update-BuildHistory {
    param([System.Collections.IDictionary]$StatusData)

    $status = [string]$StatusData.status
    if ($status -eq "RUNNING") {
        $script:lastRecordedStatus = ""
        return
    }

    if ($terminalStatuses -notcontains $status -or $script:lastRecordedStatus -eq $status) {
        return
    }

    $entry = [ordered]@{
        status = $status
        stage = $StatusData.stage
        elapsed_time = $StatusData.elapsed_time
        total_actions = $StatusData.total_actions
        first_error = $StatusData.first_error
        completed_at = $StatusData.last_update
    }

    $script:history = @($entry) + @($script:history) | Select-Object -First $HistoryLimit
    $script:lastRecordedStatus = $status
    Save-History -Items $script:history
}

function Send-WebhookNotification {
    param([System.Collections.IDictionary]$StatusData)

    if (!$WebhookUrl) {
        return
    }

    $status = [string]$StatusData.status
    if ($status -eq "RUNNING") {
        $script:lastNotificationKey = ""
        return
    }

    if ($terminalStatuses -notcontains $status) {
        return
    }

    $key = "$ProjectName|$status"
    if ($key -eq $script:lastNotificationKey) {
        return
    }

    $script:lastNotificationKey = $key
    $message = "$ProjectName build $status in $($StatusData.elapsed_time)."
    if ($StatusData.first_error) {
        $message = "$message $($StatusData.first_error)"
    }

    try {
        Invoke-RestMethod -Uri $WebhookUrl -Method Post -ContentType "application/json" -Body (@{ content = $message; text = $message } | ConvertTo-Json) | Out-Null
    } catch {
        Write-Warning "Webhook notification failed: $($_.Exception.Message)"
    }
}

if ($PollSeconds -lt 1) {
    throw "PollSeconds must be 1 or greater."
}

if ($HistoryLimit -lt 1) {
    throw "HistoryLimit must be 1 or greater."
}

$history = @(Read-History) | Select-Object -First $HistoryLimit

Write-Host "Monitoring Unreal Build Tool log:" -ForegroundColor Cyan
Write-Host "  Project: $ProjectName"
Write-Host "  Log:     $LogPath"
Write-Host "  Output:  $StatusJsPath"
if (!$NoJson) {
    Write-Host "  JSON:    $StatusJsonPath"
}
if (!$NoHistory) {
    Write-Host "  History: $HistoryJsonPath"
}
Write-Host "Press Ctrl+C to stop." -ForegroundColor DarkGray

$startTime = [DateTime]::Now

while ($true) {
    $elapsed = [DateTime]::Now - $startTime

    if (Test-Path $LogPath) {
        $lines = Get-Content $LogPath -Tail 500 -ErrorAction SilentlyContinue
        $statusData = Get-BuildStatusFromLog -Lines $lines -Elapsed $elapsed
    } else {
        $statusData = New-BuildStatus `
            -Status "WAITING" `
            -Stage "Waiting" `
            -CurrentFile "Waiting for log file: $LogPath" `
            -CurrentAction 0 `
            -TotalActions 0 `
            -Progress 0 `
            -ElapsedTime ("{0:hh\:mm\:ss}" -f $elapsed) `
            -FirstError "" `
            -Errors @()
    }

    Update-SlowFileTracking -StatusData $statusData
    $statusData.slow_files = @(Get-SlowFiles)
    Update-BuildHistory -StatusData $statusData
    $statusData.history = @($history)
    Send-WebhookNotification -StatusData $statusData
    Write-BuildStatus -StatusData $statusData
    Start-Sleep -Seconds $PollSeconds
}
