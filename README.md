# Unreal Engine Build Monitor

Real-time static dashboard for watching Unreal Build Tool progress from a browser.

![Unreal Build Monitor](favicon.png)

## Features

- Works as a static page opened through `file://`
- Watches the Unreal Build Tool log with a small PowerShell script
- Shows build stage, progress, elapsed time, active file, and action count
- Extracts first-cause-style error summary lines from failed builds
- Keeps recent build history and slow-file timing data
- Supports browser notifications and optional webhook notifications
- Supports project presets through `config.js`
- Includes a lightweight local web server helper for `http://localhost`

<img width="1866" height="960" alt="image" src="https://github.com/user-attachments/assets/3e0960a8-dc08-40f3-a3c0-ce29824621ba" />

## Quick Start

1. Clone the repository.
2. Run the monitor script in PowerShell:

```powershell
.\monitor.ps1
```

3. Open `index.html` in a browser.
4. Start an Unreal build.

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
.\monitor.ps1 -WebhookUrl "https://discord.com/api/webhooks/..."
```

```powershell
.\monitor.ps1 -NoJson -NoHistory
```

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
- `build_status.js` - browser-readable sample/status payload
- `build_status.json` - optional JSON sample/status payload
- `build_history.json` - persisted recent-build history

## Notes

The dashboard loads `build_status.js` as a script instead of fetching JSON. This avoids browser security restrictions when the page is opened directly from disk.
