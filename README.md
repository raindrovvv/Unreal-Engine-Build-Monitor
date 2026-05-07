# Unreal Engine Build Monitor

Real-time static dashboard for watching Unreal Build Tool progress from a browser.

![GAS Build Monitor](favicon.png)

## Files

- `index.html` - dashboard shell
- `style.css` - glass/neon monitor styling
- `app.js` - refreshes `build_status.js` every second
- `monitor.ps1` - tails the Unreal Build Tool log and writes `build_status.js`
- `build_status.js` - browser-readable build status payload
- `build_status.json` - optional JSON snapshot

## Usage

1. Run the monitor script in PowerShell:

```powershell
.\monitor.ps1
```

2. Open `index.html` in a browser.

The script reads:

```text
%LOCALAPPDATA%\UnrealBuildTool\Log.txt
```

and writes a local `build_status.js` next to the dashboard files, so the page can update even when opened through `file://`.

