param(
    [int]$Port = 4173
)

$ErrorActionPreference = "Stop"
$root = $PSScriptRoot
$python = Get-Command python -ErrorAction SilentlyContinue
$py = Get-Command py -ErrorAction SilentlyContinue

Write-Host "Serving Unreal Build Monitor at http://localhost:$Port" -ForegroundColor Cyan
Write-Host "Root: $root"

if ($python) {
    & python -m http.server $Port --directory $root
} elseif ($py) {
    & py -m http.server $Port --directory $root
} else {
    throw "Python was not found. Install Python or open index.html directly."
}
