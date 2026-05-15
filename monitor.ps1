param(
    [string]$LogPath = "$env:LOCALAPPDATA\UnrealBuildTool\Log.txt",
    [string]$StatusJsPath = (Join-Path $PSScriptRoot "build_status.js"),
    [string]$StatusJsonPath = (Join-Path $PSScriptRoot "build_status.json"),
    [string]$HistoryJsonPath = (Join-Path $PSScriptRoot "build_history.json"),
    [string]$WebhookSettingsPath = (Join-Path $PSScriptRoot "webhook_settings.json"),
    [string]$ProjectName = "Unreal Project",
    [string]$GitRepoPath = "",
    [int]$PollSeconds = 1,
    [int]$HistoryLimit = 10,
    [int]$SlowFileLimit = 5,
    [int]$ErrorContextLines = 12,
    [int]$StallSeconds = 120,
    [switch]$NoJson,
    [switch]$NoHistory,
    [switch]$EnableWindowsToast,
    [switch]$EnableSound,
    [string]$WebhookUrl = "",
    [ValidateSet("discord", "slack")]
    [string]$WebhookProvider = "discord"
)

$ErrorActionPreference = "Stop"

$terminalStatuses = @("SUCCEEDED", "FAILED")
$history = @()
$slowFiles = @{}
$trackedFile = ""
$trackedFileStartedAt = $null
$lastRecordedStatus = ""
$lastNotificationKey = ""
$lastToastKey = ""
$lastSoundKey = ""
$lastProgressAction = -1
$lastProgressAt = [DateTime]::Now

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
        [string[]]$Errors,
        [string]$ErrorType,
        [object[]]$ErrorContext
    )

    [ordered]@{
        project_name = $ProjectName
        log_path = $LogPath
        total_actions = $TotalActions
        current_action = $CurrentAction
        current_file = $CurrentFile
        progress = $Progress
        status = $Status
        stage = $Stage
        elapsed_time = $ElapsedTime
        first_error = $FirstError
        error_type = $ErrorType
        error_context = @($ErrorContext)
        errors = @($Errors)
        stall = Get-StallInfo -Status $Status -CurrentAction $CurrentAction
        git_info = Get-GitInfo
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

function Get-GitInfo {
    if (!$GitRepoPath -or !(Test-Path $GitRepoPath)) {
        return [ordered]@{
            available = $false
            branch = ""
            commit = ""
            dirty = $false
        }
    }

    try {
        $branch = (& git -C $GitRepoPath branch --show-current 2>$null).Trim()
        $commit = (& git -C $GitRepoPath rev-parse --short HEAD 2>$null).Trim()
        $dirty = [bool]((& git -C $GitRepoPath status --porcelain 2>$null) | Select-Object -First 1)

        [ordered]@{
            available = [bool]($branch -or $commit)
            branch = $branch
            commit = $commit
            dirty = $dirty
        }
    } catch {
        [ordered]@{
            available = $false
            branch = ""
            commit = ""
            dirty = $false
        }
    }
}

function Get-StallInfo {
    param(
        [string]$Status,
        [int]$CurrentAction
    )

    if ($Status -ne "RUNNING" -or $CurrentAction -lt 1) {
        $script:lastProgressAction = $CurrentAction
        $script:lastProgressAt = [DateTime]::Now
        return [ordered]@{
            stalled = $false
            seconds = 0
            threshold_seconds = $StallSeconds
        }
    }

    if ($CurrentAction -ne $script:lastProgressAction) {
        $script:lastProgressAction = $CurrentAction
        $script:lastProgressAt = [DateTime]::Now
    }

    $seconds = [Math]::Round(([DateTime]::Now - $script:lastProgressAt).TotalSeconds, 1)
    [ordered]@{
        stalled = $seconds -ge $StallSeconds
        seconds = $seconds
        threshold_seconds = $StallSeconds
    }
}

function Write-BuildStatus {
    param([System.Collections.IDictionary]$StatusData)

    $statusDir = Split-Path $StatusJsPath
    if ($statusDir -and !(Test-Path $statusDir)) {
        New-Item -ItemType Directory -Path $statusDir -Force | Out-Null
    }

    $json = $StatusData | ConvertTo-Json -Depth 8
    $content = "window.buildStatus = $json;"

    # Retry logic for file writing to handle locking
    $maxRetries = 5
    $retryCount = 0
    $success = $false

    while (!$success -and $retryCount -lt $maxRetries) {
        try {
            # Use a temporary file and move it for atomic-like update
            $tempPath = $StatusJsPath + ".tmp"
            $content | Out-File -FilePath $tempPath -Encoding utf8 -Force
            Move-Item -Path $tempPath -Destination $StatusJsPath -Force -ErrorAction Stop
            
            if (!$NoJson) {
                $jsonTempPath = $StatusJsonPath + ".tmp"
                $json | Out-File -FilePath $jsonTempPath -Encoding utf8 -Force
                Move-Item -Path $jsonTempPath -Destination $StatusJsonPath -Force -ErrorAction Stop
            }
            $success = $true
        } catch {
            $retryCount++
            if ($retryCount -lt $maxRetries) {
                Start-Sleep -Milliseconds 100
            } else {
                Write-Warning "Failed to write build status after $maxRetries attempts: $($_.Exception.Message)"
            }
        }
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

function Test-ErrorLine {
    param([string]$Line)

    $patterns = @(
        "fatal error .+",
        "error\s+(?:C|LNK|MSB|CS)\d+:.+",
        "UHT Error:.+",
        "UnrealHeaderTool.+Error:.+",
        ":\s*error:.+",
        "BuildException:.+"
    )

    foreach ($pattern in $patterns) {
        if ($Line -match $pattern) {
            return $true
        }
    }

    $false
}

function Get-ErrorType {
    param([string]$ErrorLine)

    if (!$ErrorLine) {
        return "None"
    }

    if ($ErrorLine -match "UHT|UnrealHeaderTool") {
        return "UHT"
    }
    if ($ErrorLine -match "LNK\d+") {
        return "Linker"
    }
    if ($ErrorLine -match "MSB\d+") {
        return "MSBuild"
    }
    if ($ErrorLine -match "error\s+(?:C|CS)\d+|fatal error") {
        return "Compiler"
    }
    if ($ErrorLine -match "BuildException") {
        return "BuildTool"
    }

    "Unknown"
}

function Get-ErrorContext {
    param([string[]]$Lines)

    $errorIndex = -1
    for ($index = 0; $index -lt $Lines.Count; $index++) {
        if (Test-ErrorLine -Line $Lines[$index]) {
            $errorIndex = $index
            break
        }
    }

    if ($errorIndex -lt 0) {
        return @()
    }

    $start = [Math]::Max(0, $errorIndex - $ErrorContextLines)
    $end = [Math]::Min($Lines.Count - 1, $errorIndex + $ErrorContextLines)
    $context = @()

    for ($index = $start; $index -le $end; $index++) {
        $context += [pscustomobject]@{
            line = $index + 1
            text = $Lines[$index]
            is_error = $index -eq $errorIndex
        }
    }

    @($context)
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
    $firstError = $errors | Select-Object -First 1
    $errorType = Get-ErrorType -ErrorLine $firstError
    $errorContext = @(Get-ErrorContext -Lines $Lines)
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
        -FirstError $firstError `
        -Errors $errors `
        -ErrorType $errorType `
        -ErrorContext $errorContext
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
        error_type = $StatusData.error_type
        error_context = @($StatusData.error_context)
        slow_files = @($StatusData.slow_files)
        git_info = $StatusData.git_info
        completed_at = $StatusData.last_update
    }

    $script:history = @($entry) + @($script:history) | Select-Object -First $HistoryLimit
    $script:lastRecordedStatus = $status
    Save-History -Items $script:history
}

function Send-WebhookNotification {
    param([System.Collections.IDictionary]$StatusData)

    $status = [string]$StatusData.status
    if ($status -eq "RUNNING") {
        $script:lastNotificationKey = ""
        return
    }

    $settings = Get-WebhookSettings
    $targets = @()
    if ($WebhookUrl) {
        $targets += [ordered]@{
            provider = $WebhookProvider
            url = $WebhookUrl
            enabled = $true
        }
    }
    if ($settings.discord.enabled -and $settings.discord.url) {
        $targets += [ordered]@{
            provider = "discord"
            url = $settings.discord.url
            enabled = $true
        }
    }
    if ($settings.slack.enabled -and $settings.slack.url) {
        $targets += [ordered]@{
            provider = "slack"
            url = $settings.slack.url
            enabled = $true
        }
    }

    if ($targets.Count -lt 1) {
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

    foreach ($target in $targets) {
        Send-WebhookTarget -Provider $target.provider -Url $target.url -StatusData $StatusData
    }
}

function Get-WebhookSettings {
    $emptySettings = [pscustomobject]@{
        discord = [pscustomobject]@{ enabled = $false; url = "" }
        slack = [pscustomobject]@{ enabled = $false; url = "" }
    }

    if (!(Test-Path $WebhookSettingsPath)) {
        return $emptySettings
    }

    try {
        $settings = Get-Content $WebhookSettingsPath -Raw | ConvertFrom-Json
        if ($null -eq $settings.discord) {
            $settings | Add-Member -NotePropertyName discord -NotePropertyValue $emptySettings.discord
        }
        if ($null -eq $settings.slack) {
            $settings | Add-Member -NotePropertyName slack -NotePropertyValue $emptySettings.slack
        }
        return $settings
    } catch {
        Write-Warning "Could not read webhook settings: $WebhookSettingsPath"
        return $emptySettings
    }
}

function Send-WebhookTarget {
    param(
        [string]$Provider,
        [string]$Url,
        [System.Collections.IDictionary]$StatusData
    )

    $status = [string]$StatusData.status
    $summary = "$ProjectName build $status in $($StatusData.elapsed_time)."
    $detail = if ($StatusData.first_error) { [string]$StatusData.first_error } else { [string]$StatusData.current_file }

    if ($Provider -eq "slack") {
        $payload = @{
            text = $summary
            blocks = @(
                @{
                    type = "header"
                    text = @{
                        type = "plain_text"
                        text = "$ProjectName build $status"
                    }
                },
                @{
                    type = "section"
                    fields = @(
                        @{ type = "mrkdwn"; text = "*Status:*`n$status" },
                        @{ type = "mrkdwn"; text = "*Elapsed:*`n$($StatusData.elapsed_time)" },
                        @{ type = "mrkdwn"; text = "*Stage:*`n$($StatusData.stage)" },
                        @{ type = "mrkdwn"; text = "*Actions:*`n$($StatusData.current_action) / $($StatusData.total_actions)" }
                    )
                },
                @{
                    type = "section"
                    text = @{
                        type = "mrkdwn"
                        text = "*Summary:*`n$detail"
                    }
                }
            )
        }
    } else {
        $color = if ($status -eq "SUCCEEDED") { 3066993 } else { 15158332 }
        $payload = @{
            content = $summary
            embeds = @(
                @{
                    title = "$ProjectName build $status"
                    description = $detail
                    color = $color
                    fields = @(
                        @{ name = "Stage"; value = [string]$StatusData.stage; inline = $true },
                        @{ name = "Elapsed"; value = [string]$StatusData.elapsed_time; inline = $true },
                        @{ name = "Actions"; value = "$($StatusData.current_action) / $($StatusData.total_actions)"; inline = $true }
                    )
                }
            )
        }
    }

    try {
        Invoke-RestMethod -Uri $Url -Method Post -ContentType "application/json" -Body ($payload | ConvertTo-Json -Depth 8) | Out-Null
    } catch {
        Write-Warning "$Provider webhook notification failed: $($_.Exception.Message)"
    }
}

function Send-LocalNotifications {
    param([System.Collections.IDictionary]$StatusData)

    $status = [string]$StatusData.status
    if ($status -eq "RUNNING") {
        $script:lastToastKey = ""
        $script:lastSoundKey = ""
        return
    }

    if ($terminalStatuses -notcontains $status) {
        return
    }

    $key = "$ProjectName|$status"
    $title = "$ProjectName build $status"
    $message = if ($StatusData.first_error) {
        [string]$StatusData.first_error
    } else {
        "Finished in $($StatusData.elapsed_time)."
    }

    if ($EnableWindowsToast -and $key -ne $script:lastToastKey) {
        $script:lastToastKey = $key
        Show-WindowsNotification -Title $title -Message $message
    }

    if ($EnableSound -and $key -ne $script:lastSoundKey) {
        $script:lastSoundKey = $key
        Play-BuildSound -Status $status
    }
}

function Show-WindowsNotification {
    param(
        [string]$Title,
        [string]$Message
    )

    try {
        $burntToast = Get-Command New-BurntToastNotification -ErrorAction SilentlyContinue
        if ($burntToast) {
            New-BurntToastNotification -Text $Title, $Message | Out-Null
            return
        }

        Add-Type -AssemblyName System.Windows.Forms
        Add-Type -AssemblyName System.Drawing
        $notifyIcon = New-Object System.Windows.Forms.NotifyIcon
        $notifyIcon.Icon = [System.Drawing.SystemIcons]::Information
        $notifyIcon.Visible = $true
        $notifyIcon.ShowBalloonTip(5000, $Title, $Message, [System.Windows.Forms.ToolTipIcon]::Info)
        Start-Sleep -Milliseconds 250
        $notifyIcon.Dispose()
    } catch {
        Write-Warning "Windows notification failed: $($_.Exception.Message)"
    }
}

function Play-BuildSound {
    param([string]$Status)

    try {
        if ($Status -eq "SUCCEEDED") {
            [Console]::Beep(880, 160)
            [Console]::Beep(1175, 180)
        } else {
            [Console]::Beep(440, 220)
            [Console]::Beep(330, 260)
        }
    } catch {
        Write-Warning "Sound notification failed: $($_.Exception.Message)"
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
if ($GitRepoPath) {
    Write-Host "  Git:     $GitRepoPath"
}
Write-Host "  Output:  $StatusJsPath"
if (!$NoJson) {
    Write-Host "  JSON:    $StatusJsonPath"
}
if (!$NoHistory) {
    Write-Host "  History: $HistoryJsonPath"
}
Write-Host "  Webhook settings: $WebhookSettingsPath"
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
            -Errors @() `
            -ErrorType "None" `
            -ErrorContext @()
    }

    Update-SlowFileTracking -StatusData $statusData
    $statusData.slow_files = @(Get-SlowFiles)
    Update-BuildHistory -StatusData $statusData
    $statusData.history = @($history)
    Send-WebhookNotification -StatusData $statusData
    Send-LocalNotifications -StatusData $statusData
    Write-BuildStatus -StatusData $statusData
    Start-Sleep -Seconds $PollSeconds
}
