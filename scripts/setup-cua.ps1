param(
  [string]$UsbRoot = 'D:\SENIOR_AI',
  [switch]$SkipInstall
)

$ErrorActionPreference = 'Stop'
$Repo = Split-Path -Parent $PSScriptRoot
$EnvFile = Join-Path $Repo '.env'
$BrowserSocket = '\\.\pipe\senior-cua-browser'
$DesktopSocket = '\\.\pipe\senior-cua-desktop'

function Fail([string]$Message) {
  Write-Host "FAILED: $Message" -ForegroundColor Red
  exit 1
}

function Resolve-CuaDriver {
  $command = Get-Command cua-driver.exe -ErrorAction SilentlyContinue
  if ($command) { return $command.Source }
  $candidate = Join-Path $env:LOCALAPPDATA 'Programs\trycua\cua-driver-rs\bin\cua-driver.exe'
  if (Test-Path $candidate) { return $candidate }
  return $null
}

function Set-DotEnv([string]$Name, [string]$Value) {
  if (-not (Test-Path $EnvFile)) { Fail ".env is missing: $EnvFile" }
  $lines = [System.Collections.Generic.List[string]]::new()
  foreach ($line in [IO.File]::ReadAllLines($EnvFile)) { [void]$lines.Add($line) }
  $prefix = "$Name="
  $found = $false
  for ($i = 0; $i -lt $lines.Count; $i++) {
    if ($lines[$i].StartsWith($prefix, [StringComparison]::Ordinal)) {
      $lines[$i] = "$Name=$Value"
      $found = $true
    }
  }
  if (-not $found) { [void]$lines.Add("$Name=$Value") }
  [IO.File]::WriteAllLines($EnvFile, $lines, [Text.UTF8Encoding]::new($false))
}

Write-Host ""
Write-Host "== INSTALL / VERIFY CUA DRIVER ==" -ForegroundColor Cyan
$Driver = Resolve-CuaDriver
if (-not $Driver -and -not $SkipInstall) {
  Write-Host 'Installing official Cua Driver release for the current Windows user...'
  $installer = Invoke-RestMethod -Uri 'https://cua.ai/driver/install.ps1'
  & ([scriptblock]::Create([string]$installer))
  $Driver = Resolve-CuaDriver
}
if (-not $Driver) { Fail 'cua-driver is not installed.' }

& $Driver --version
if ($LASTEXITCODE -ne 0) { Fail 'cua-driver --version failed.' }
$doctor = & $Driver doctor 2>&1
if ($LASTEXITCODE -ne 0) {
  Write-Warning 'cua-driver doctor reported host warnings/errors. Bounded runtime verification will decide acceptance.'
  $doctor | ForEach-Object { Write-Host $_ }
}

$configDir = Join-Path $UsbRoot 'senior\config'
$logsDir = Join-Path $UsbRoot 'logs'
New-Item -ItemType Directory -Force -Path $configDir,$logsDir | Out-Null

Write-Host ""
Write-Host "== WRITE BOUNDED CUA MANIFESTS ==" -ForegroundColor Cyan
$browserManifest = @'
version: 3
expires_after: 24h
idle_timeout: 12h

allow:
  tools:
    - list_windows
    - get_browser_state
    - health_report
    - check_permissions
    - start_session
    - end_session
    - launch_app
    - browser_prepare
    - browser_navigate
    - browser_click
    - browser_type
    - browser_dialog
    - browser_set_input_files
    - browser_download

resources:
  browser:
    profiles:
      - kind: existing_profile
    origins:
      - https://admin.shopify.com
      - https://accounts.shopify.com
      - https://app.metricool.com
      - https://kdp.amazon.com
      - https://www.amazon.com
      - https://mail.google.com
      - https://accounts.google.com
      - https://drive.google.com
      - https://www.canva.com
      - https://printify.com
      - https://app.klaviyo.com
      - https://business.facebook.com
      - https://adsmanager.facebook.com
      - https://www.facebook.com
      - https://www.instagram.com
      - https://www.tiktok.com
      - https://ads.tiktok.com
      - https://www.pinterest.com
      - https://www.youtube.com
      - https://studio.youtube.com
      - https://github.com

  desktop:
    display: false
'@
[IO.File]::WriteAllText((Join-Path $configDir 'cua-browser.yaml'), $browserManifest, [Text.UTF8Encoding]::new($false))

$allowedApps = @(
  'C:\Windows\System32\notepad.exe',
  'C:\Program Files\Docker\Docker\Docker Desktop.exe',
  (Join-Path $env:LOCALAPPDATA 'Programs\Microsoft VS Code\Code.exe')
) | Where-Object { $_ -and (Test-Path $_) } | Select-Object -Unique

if (@($allowedApps).Count -eq 0) {
  Fail 'No approved non-browser desktop application was found for the Cua Desktop manifest.'
}

$appBlocks = @()
foreach ($app in $allowedApps) {
  $safe = $app.Replace("'", "''")
  $appBlocks += [string]::Join([Environment]::NewLine, @(
    "    - executable: '$safe'",
    '      launch: true',
    '      windows: all',
    '      terminate: driver_launched'
  ))
}
$appYaml = [string]::Join([Environment]::NewLine, $appBlocks)

$desktopManifest = @"
version: 3
expires_after: 24h
idle_timeout: 12h

allow:
  tools:
    - list_apps
    - list_windows
    - get_window_state
    - health_report
    - check_permissions
    - verify_state
    - start_session
    - end_session
    - launch_app
    - click
    - double_click
    - type_text
    - press_key
    - hotkey
    - scroll
    - invoke_menu
    - set_window_frame

resources:
  apps:
$appYaml

  desktop:
    display: false
"@
[IO.File]::WriteAllText((Join-Path $configDir 'cua-desktop.yaml'), $desktopManifest, [Text.UTF8Encoding]::new($false))

Write-Host "Browser manifest: $(Join-Path $configDir 'cua-browser.yaml')"
Write-Host "Desktop manifest: $(Join-Path $configDir 'cua-desktop.yaml')"

Write-Host ""
Write-Host "== ENABLE OPENBOT CUA ==" -ForegroundColor Cyan
Set-DotEnv 'OPENBOT_CUA_ENABLED' 'true'
Set-DotEnv 'CUA_DRIVER_BIN' ('"' + $Driver + '"')
Set-DotEnv 'CUA_BROWSER_SOCKET' $BrowserSocket
Set-DotEnv 'CUA_DESKTOP_SOCKET' $DesktopSocket

& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'start-cua.ps1') -UsbRoot $UsbRoot -Driver $Driver
if ($LASTEXITCODE -ne 0) { Fail 'Cua bounded runtimes failed to start.' }

& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'verify-cua.ps1') -UsbRoot $UsbRoot -Driver $Driver
if ($LASTEXITCODE -ne 0) { Fail 'Cua bounded verification failed.' }

Write-Host ""
Write-Host "CUA SETUP = PASS" -ForegroundColor Green
Write-Host 'OpenBot will bootstrap governed Cua Browser + Cua Desktop connectors on its next server start.'
