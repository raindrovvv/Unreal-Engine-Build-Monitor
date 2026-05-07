# Unreal Engine Build Monitor

Real-time static dashboard for watching Unreal Build Tool progress from a browser.

![Unreal Build Monitor](favicon.png)

## Features

- Works as a static page opened through `file://`
- Watches the Unreal Build Tool log with a small PowerShell script
- Configurable dashboard title, subtitle, status payload path, and refresh interval
- Configurable log path for custom Unreal or CI workflows
- Writes both `build_status.js` for the browser and `build_status.json` for other tools

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

and writes `build_status.js` next to the dashboard files.

<img width="1866" height="960" alt="image" src="https://github.com/user-attachments/assets/3e0960a8-dc08-40f3-a3c0-ce29824621ba" />

## Configuration

Edit `config.js` to customize the browser dashboard:

```js
window.buildMonitorConfig = {
    title: 'My Project Build Monitor',
    subtitle: 'Unreal Engine 5.x Compilation Status',
    statusFile: 'build_status.js',
    refreshMs: 1000
};
```

Use PowerShell options to customize where build data comes from or where it is written:

```powershell
.\monitor.ps1 -LogPath "D:\Logs\UnrealBuildTool.log"
```

```powershell
.\monitor.ps1 -StatusJsPath "D:\Dashboard\build_status.js" -PollSeconds 2
```

```powershell
.\monitor.ps1 -NoJson
```

## Files

- `index.html` - dashboard shell
- `style.css` - glass/neon monitor styling
- `config.js` - user-facing dashboard settings
- `app.js` - refreshes the status payload every second by default
- `monitor.ps1` - tails the Unreal Build Tool log and writes status files
- `build_status.js` - browser-readable sample/status payload
- `build_status.json` - optional JSON sample/status payload

## Notes

The dashboard loads `build_status.js` as a script instead of fetching JSON. This avoids browser security restrictions when the page is opened directly from disk.
