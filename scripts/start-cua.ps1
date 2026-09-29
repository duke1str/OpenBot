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
  if ($Requested -and (Test-Path $Requested)) {
    return (Resolve-Path $Requested).Path
  }
  $command = Get-Command cua-driver.exe -ErrorAction SilentlyContinue
  if ($command) { return $command.Source }
  $candidate = Join-Path $env:LOCALAPPDATA 'Programs\trycua\cua-driver-rs\bin\cua-driver.exe'
  if (Test-Path $candidate) { return $candidate }
  Fail 'cua-driver is not installed. Run scripts/setup-cua.ps1 first.'
}

function Test-CuaRuntime([string]$Exe, [string]$Socket) {
  try {
    $output = & $Exe call health_report '{}' --socket $Socket 2>$null
    return ($LASTEXITCODE -eq 0 -and [string]::Join([Environment]::NewLine, $output).Length -gt 0)
  } catch {
    return $false
  }
}

function Start-CuaRuntime(
  [string]$Exe,
  [string]$Socket,
  [string]$Manifest,
  [string]$Stdout,
  [string]$Stderr,
  [string]$Name
) {
  if (-not (Test-Path $Manifest)) { Fail "$Name capability manifest is missing: $Manifest" }

  # Always restart an existing bounded daemon. Capability manifests expire by design;
  # reusing a healthy-but-expired daemon would make Senior look available while every real action
  # is denied. A normal Senior start therefore refreshes the reviewed bounded authorization window.
  if (Test-CuaRuntime $Exe $Socket) {
    & $Exe stop --socket $Socket *> $null
    Start-Sleep -Milliseconds 500
  } else {
    & $Exe stop --socket $Socket *> $null
  }
  Start-Sleep -Milliseconds 500
  Remove-Item $Stdout,$Stderr -Force -ErrorAction SilentlyContinue

  $args = @(
    'serve',
    '--socket', $Socket,
    '--permission-mode', 'bounded',
    '--capability-manifest', $Manifest,
    '--approve-capability-manifest',
    '--no-overlay'
  )

  Start-Process -FilePath $Exe -ArgumentList $args -WindowStyle Hidden -RedirectStandardOutput $Stdout -RedirectStandardError $Stderr | Out-Null

  for ($i = 0; $i -lt 40; $i++) {
    if (Test-CuaRuntime $Exe $Socket) { break }
    Start-Sleep -Milliseconds 500
  }

  if (-not (Test-CuaRuntime $Exe $Socket)) {
    $detail = ''
    if (Test-Path $Stderr) {
      $detail = [string]::Join([Environment]::NewLine, (Get-Content $Stderr -Tail 30 -ErrorAction SilentlyContinue))
    }
    Fail "$Name did not become ready. $detail"
  }

  Write-Host "$Name: READY" -ForegroundColor Green
}

$Driver = Resolve-CuaDriver $Driver
$configDir = Join-Path $UsbRoot 'senior\config'
$logsDir = Join-Path $UsbRoot 'logs'
New-Item -ItemType Directory -Force -Path $configDir,$logsDir | Out-Null

$browserManifest = Join-Path $configDir 'cua-browser.yaml'
$desktopManifest = Join-Path $configDir 'cua-desktop.yaml'

Write-Host ""
Write-Host "== START CUA BOUNDED RUNTIMES ==" -ForegroundColor Cyan
Write-Host "Driver: $Driver"
Start-CuaRuntime $Driver $BrowserSocket $browserManifest (Join-Path $logsDir 'cua-browser.log') (Join-Path $logsDir 'cua-browser-error.log') 'CUA Browser'
Start-CuaRuntime $Driver $DesktopSocket $desktopManifest (Join-Path $logsDir 'cua-desktop.log') (Join-Path $logsDir 'cua-desktop-error.log') 'CUA Desktop'

Write-Host "CUA BOUNDED RUNTIMES = READY" -ForegroundColor Green
