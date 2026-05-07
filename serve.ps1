param(
    [int]$Port = 4173
)

$ErrorActionPreference = "Stop"
$root = $PSScriptRoot
$settingsPath = Join-Path $root "webhook_settings.json"
$listener = [System.Net.HttpListener]::new()
$listener.Prefixes.Add("http://localhost:$Port/")

function Get-ContentType {
    param([string]$Path)

    switch ([System.IO.Path]::GetExtension($Path).ToLowerInvariant()) {
        ".html" { "text/html; charset=utf-8" }
        ".css" { "text/css; charset=utf-8" }
        ".js" { "application/javascript; charset=utf-8" }
        ".json" { "application/json; charset=utf-8" }
        ".png" { "image/png" }
        default { "application/octet-stream" }
    }
}

function Get-DefaultWebhookSettings {
    @{
        discord = @{ enabled = $false; url = "" }
        slack = @{ enabled = $false; url = "" }
    }
}

function Write-JsonResponse {
    param(
        [System.Net.HttpListenerResponse]$Response,
        [object]$Data,
        [int]$StatusCode = 200
    )

    $json = $Data | ConvertTo-Json -Depth 8
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
    $Response.StatusCode = $StatusCode
    $Response.ContentType = "application/json; charset=utf-8"
    $Response.ContentLength64 = $bytes.Length
    $Response.OutputStream.Write($bytes, 0, $bytes.Length)
}

function Read-RequestBody {
    param([System.Net.HttpListenerRequest]$Request)

    $reader = [System.IO.StreamReader]::new($Request.InputStream, $Request.ContentEncoding)
    try {
        $reader.ReadToEnd()
    } finally {
        $reader.Dispose()
    }
}

function Save-WebhookSettings {
    param([object]$Settings)

    $safeSettings = Get-DefaultWebhookSettings
    if ($Settings.discord) {
        $safeSettings.discord.enabled = [bool]$Settings.discord.enabled
        $safeSettings.discord.url = [string]$Settings.discord.url
    }
    if ($Settings.slack) {
        $safeSettings.slack.enabled = [bool]$Settings.slack.enabled
        $safeSettings.slack.url = [string]$Settings.slack.url
    }

    $safeSettings | ConvertTo-Json -Depth 8 | Out-File -FilePath $settingsPath -Encoding utf8 -Force
    $safeSettings
}

function Handle-WebhookApi {
    param(
        [System.Net.HttpListenerRequest]$Request,
        [System.Net.HttpListenerResponse]$Response
    )

    if ($Request.HttpMethod -eq "GET") {
        if (Test-Path $settingsPath) {
            try {
                Write-JsonResponse -Response $Response -Data (Get-Content $settingsPath -Raw | ConvertFrom-Json)
            } catch {
                Write-JsonResponse -Response $Response -Data (Get-DefaultWebhookSettings)
            }
        } else {
            Write-JsonResponse -Response $Response -Data (Get-DefaultWebhookSettings)
        }
        return
    }

    if ($Request.HttpMethod -eq "POST") {
        $body = Read-RequestBody -Request $Request
        $settings = $body | ConvertFrom-Json
        Write-JsonResponse -Response $Response -Data (Save-WebhookSettings -Settings $settings)
        return
    }

    Write-JsonResponse -Response $Response -Data @{ error = "Method not allowed" } -StatusCode 405
}

function Handle-StaticFile {
    param(
        [System.Net.HttpListenerRequest]$Request,
        [System.Net.HttpListenerResponse]$Response
    )

    $relativePath = [System.Uri]::UnescapeDataString($Request.Url.AbsolutePath.TrimStart("/"))
    if (!$relativePath) {
        $relativePath = "index.html"
    }

    $candidate = Join-Path $root $relativePath
    $resolvedRoot = [System.IO.Path]::GetFullPath($root)
    $resolvedPath = [System.IO.Path]::GetFullPath($candidate)

    if (!$resolvedPath.StartsWith($resolvedRoot, [System.StringComparison]::OrdinalIgnoreCase) -or !(Test-Path $resolvedPath)) {
        $Response.StatusCode = 404
        return
    }

    $bytes = [System.IO.File]::ReadAllBytes($resolvedPath)
    $Response.StatusCode = 200
    $Response.ContentType = Get-ContentType -Path $resolvedPath
    $Response.ContentLength64 = $bytes.Length
    $Response.OutputStream.Write($bytes, 0, $bytes.Length)
}

Write-Host "Serving Unreal Build Monitor at http://localhost:$Port" -ForegroundColor Cyan
Write-Host "Root: $root"
Write-Host "Webhook settings: $settingsPath"
Write-Host "Press Ctrl+C to stop." -ForegroundColor DarkGray

$listener.Start()
try {
    while ($listener.IsListening) {
        $context = $listener.GetContext()
        try {
            if ($context.Request.Url.AbsolutePath -eq "/api/webhooks") {
                Handle-WebhookApi -Request $context.Request -Response $context.Response
            } else {
                Handle-StaticFile -Request $context.Request -Response $context.Response
            }
        } catch {
            Write-JsonResponse -Response $context.Response -Data @{ error = $_.Exception.Message } -StatusCode 500
        } finally {
            $context.Response.OutputStream.Close()
        }
    }
} finally {
    $listener.Stop()
}
