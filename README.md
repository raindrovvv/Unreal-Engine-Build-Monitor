# Unreal Engine Build Monitor

Real-time static dashboard for watching Unreal Build Tool progress from a browser.

![Unreal Build Monitor](favicon.png)

## Features

- Works as a static page opened through `file://`
- Watches the Unreal Build Tool log with a small PowerShell script
- Shows build stage, progress, elapsed time, active file, and action count
- Extracts first-cause-style error summary lines from failed builds
- Shows nearby log context around the first error
- Classifies failures as UHT, Compiler, Linker, MSBuild, BuildTool, or Unknown
- Detects stalled builds when the current action stops changing
- Shows optional Git branch, commit, and dirty state
- Keeps recent build history and slow-file timing data
- Opens build history details in a modal
- Supports browser notifications, Discord webhooks, and Slack webhooks
- Supports opt-in local Windows notifications and sound cues from `monitor.ps1`
- Supports project presets through `config.js`
- Includes a lightweight local web server helper for `http://localhost`
- Includes `start-dashboard.ps1` to launch the server and monitor together
- Includes dashboard buttons for testing Discord and Slack webhooks

<img width="1866" height="960" alt="image" src="https://github.com/user-attachments/assets/3e0960a8-dc08-40f3-a3c0-ce29824621ba" />

## Quick Start

### One-command start

```powershell
.\start-dashboard.ps1 -ProjectName "My Game" -GitRepoPath "D:\Unreal Projects\MyGame" -OpenBrowser
```

This starts:

- `serve.ps1` for `http://localhost:4173`
- `monitor.ps1` for the Unreal Build Tool log

### Manual start

1. Clone the repository.
2. Run the local dashboard server:

```powershell
.\serve.ps1 -Port 4173
```

3. Open `http://localhost:4173`.
4. Run the monitor script in another PowerShell:

```powershell
.\monitor.ps1
```

5. Start an Unreal build.

By default, the script reads:

```text
%LOCALAPPDATA%\UnrealBuildTool\Log.txt
```

and writes `build_status.js`, `build_status.json`, and `build_history.json` next to the dashboard files.

## Configuration

Edit `config.js` to customize the browser dashboard:

```js
window.buildMonitorConfig = {
    title: 'Unreal Build Monitor',
    subtitle: 'Real-time Unreal Engine Compilation Status',
    statusFile: 'build_status.js',
    refreshMs: 1000,
    notifications: {
        browser: true
    },
    projects: [
        {
            id: 'game',
            name: 'My Game',
            title: 'My Game Build Monitor',
            subtitle: 'Unreal Engine Compilation Status',
            statusFile: 'build_status.js'
        }
    ]
};
```

Use PowerShell options to customize where build data comes from or where it is written:

```powershell
.\monitor.ps1 -ProjectName "My Game" -LogPath "D:\Logs\UnrealBuildTool.log"
```

```powershell
.\monitor.ps1 -StatusJsPath "D:\Dashboard\build_status.js" -PollSeconds 2
```

```powershell
.\monitor.ps1 -GitRepoPath "D:\Unreal Projects\MyGame" -StallSeconds 180
```

```powershell
.\monitor.ps1 -EnableWindowsToast -EnableSound
```

```powershell
.\monitor.ps1 -NoJson -NoHistory
```

## Webhook Notifications

The easiest setup path is the local server mode:

```powershell
.\serve.ps1 -Port 4173
```

Open `http://localhost:4173`, paste your Discord or Slack webhook URL in the Webhook Notifications panel, enable it, and click **Save Webhooks**. The dashboard writes `webhook_settings.json`, and `monitor.ps1` reads it automatically.

Use **Test Discord** and **Test Slack** from the dashboard to verify URLs before waiting for a real build. Invalid webhook URL formats are highlighted before saving.

You can still pass a webhook from the command line:

```powershell
.\monitor.ps1 -WebhookProvider discord -WebhookUrl "https://discord.com/api/webhooks/..."
```

```powershell
.\monitor.ps1 -WebhookProvider slack -WebhookUrl "https://hooks.slack.com/services/..."
```

Discord notifications use embeds. Slack notifications use Block Kit blocks.

## Local Server Mode

The dashboard works from disk, but a local server is useful for phones, tablets, or cleaner browser permissions:

```powershell
.\serve.ps1 -Port 4173
```

Then open:

```text
http://localhost:4173
```

## Files

- `index.html` - dashboard shell
- `style.css` - dashboard styling
- `config.js` - dashboard settings and project presets
- `app.js` - reads status payloads and renders the dashboard
- `monitor.ps1` - tails the Unreal Build Tool log and writes status files
- `serve.ps1` - optional local static server helper
- `start-dashboard.ps1` - starts the dashboard server and monitor together
- `webhook_settings.sample.json` - example webhook settings file
- `build_status.js` - browser-readable sample/status payload
- `build_status.json` - optional JSON sample/status payload
- `build_history.json` - persisted recent-build history

## Deliberately Deferred

The dashboard does not execute build commands yet. Running local build commands from a browser needs an explicit allowlist and local-only safety model before it should ship.

## Release Packaging

For a GitHub release:

1. Download the source zip from the release page.
2. Extract it anywhere.
3. Run:

```powershell
.\start-dashboard.ps1 -ProjectName "My Game" -GitRepoPath "D:\Unreal Projects\MyGame" -OpenBrowser
```

4. Configure webhooks from `http://localhost:4173`.

## Notes

The dashboard loads `build_status.js` as a script instead of fetching JSON. This avoids browser security restrictions when the page is opened directly from disk.
