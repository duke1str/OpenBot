param(
  [string]$UsbRoot = 'D:\SENIOR_AI',
  [string]$Driver = '',
  [string]$BrowserSocket = '\\.\pipe\senior-cua-browser',
  [string]$DesktopSocket = '\\.\pipe\senior-cua-desktop'
)

$ErrorActionPreference = 'Stop'

function Fail([string]$Message) {
  Write-Host "FAILED: $Message" -ForegroundColor Red
  exit 1
}

function Resolve-CuaDriver([string]$Requested) {
  if ($Requested -and (Test-Path $Requested)) { return (Resolve-Path $Requested).Path }
  $command = Get-Command cua-driver.exe -ErrorAction SilentlyContinue
  if ($command) { return $command.Source }
  $candidate = Join-Path $env:LOCALAPPDATA 'Programs\trycua\cua-driver-rs\bin\cua-driver.exe'
  if (Test-Path $candidate) { return $candidate }
  Fail 'cua-driver executable was not found.'
}

function Call-Cua([string]$Exe, [string]$Socket, [string]$Tool, [string]$Args = '{}') {
  $output = & $Exe call $Tool $Args --socket $Socket 2>&1
  if ($LASTEXITCODE -ne 0) {
    Fail "CUA $Tool failed on $Socket. $([string]::Join([Environment]::NewLine, $output))"
  }
  return [string]::Join([Environment]::NewLine, $output)
}

$Driver = Resolve-CuaDriver $Driver
$browserManifest = Join-Path $UsbRoot 'senior\config\cua-browser.yaml'
$desktopManifest = Join-Path $UsbRoot 'senior\config\cua-desktop.yaml'
if (-not (Test-Path $browserManifest)) { Fail "Browser manifest missing: $browserManifest" }
if (-not (Test-Path $desktopManifest)) { Fail "Desktop manifest missing: $desktopManifest" }

Write-Host ""
Write-Host "== VERIFY CUA DRIVER ==" -ForegroundColor Cyan
& $Driver --version
if ($LASTEXITCODE -ne 0) { Fail 'cua-driver --version failed.' }

$browserPerm = Call-Cua $Driver $BrowserSocket 'check_permissions'
if ($browserPerm -notmatch '(?i)bounded') { Fail 'CUA Browser is not reporting bounded permission mode.' }
$null = Call-Cua $Driver $BrowserSocket 'health_report'
$null = Call-Cua $Driver $BrowserSocket 'list_windows'
Write-Host 'CUA Browser bounded/read path: PASS' -ForegroundColor Green

$desktopPerm = Call-Cua $Driver $DesktopSocket 'check_permissions'
if ($desktopPerm -notmatch '(?i)bounded') { Fail 'CUA Desktop is not reporting bounded permission mode.' }
$null = Call-Cua $Driver $DesktopSocket 'health_report'
$null = Call-Cua $Driver $DesktopSocket 'list_apps'
Write-Host 'CUA Desktop bounded/read path: PASS' -ForegroundColor Green

# Prove omitted cross-boundary tools fail closed. A browser-origin runtime must reject generic
# desktop input, and the native-app runtime must reject typed-browser inspection.
$browserDenied = & $Driver call click '{}' --socket $BrowserSocket 2>&1
if ($LASTEXITCODE -eq 0 -or ([string]::Join([Environment]::NewLine, $browserDenied) -notmatch '(?i)(permission_denied|not allowed|denied)')) {
  Fail 'CUA Browser did not prove denial of generic desktop click.'
}
$desktopDenied = & $Driver call get_browser_state '{}' --socket $DesktopSocket 2>&1
if ($LASTEXITCODE -eq 0 -or ([string]::Join([Environment]::NewLine, $desktopDenied) -notmatch '(?i)(permission_denied|not allowed|denied)')) {
  Fail 'CUA Desktop did not prove denial of typed-browser access.'
}
Write-Host 'CUA cross-boundary denial checks: PASS' -ForegroundColor Green

$browserText = Get-Content $browserManifest -Raw
$desktopText = Get-Content $desktopManifest -Raw
foreach ($forbidden in @('click','type_text','press_key','get_window_state','get_desktop_state')) {
  $pattern = '(?m)^\s*-\s+' + [regex]::Escape($forbidden) + '\s*$'
  if ($browserText -match $pattern) {
    Fail "Browser manifest contains forbidden generic desktop tool: $forbidden"
  }
}
if ($desktopText -match '(?i)(chrome\.exe|msedge\.exe|firefox\.exe|brave\.exe)') {
  Fail 'Desktop manifest names a browser executable and could bypass the typed-browser origin boundary.'
}

Write-Host ""
Write-Host "CUA BOUNDED INTEGRATION = PASS" -ForegroundColor Green
