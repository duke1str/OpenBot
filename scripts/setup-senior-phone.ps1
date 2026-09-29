param(
  [int]$Port = 3010
)

$ErrorActionPreference = 'Stop'

function Fail([string]$Message) {
  Write-Host "FAILED: $Message" -ForegroundColor Red
  exit 1
}

function Resolve-Tailscale {
  $command = Get-Command tailscale.exe -ErrorAction SilentlyContinue
  if ($command) { return $command.Source }
  $candidate = 'C:\Program Files\Tailscale\tailscale.exe'
  if (Test-Path $candidate) { return $candidate }
  return $null
}

Write-Host ""
Write-Host "== SENIOR PHONE ACCESS / TAILSCALE ==" -ForegroundColor Cyan
$tailscale = Resolve-Tailscale

if (-not $tailscale) {
  $winget = Get-Command winget.exe -ErrorAction SilentlyContinue
  if (-not $winget) {
    Fail 'Tailscale is not installed and winget is unavailable. Install Tailscale for Windows, then rerun this script.'
  }
  Write-Host 'Installing Tailscale for Windows. Windows may request administrator approval...'
  & $winget.Source install --id tailscale.tailscale --exact --accept-package-agreements --accept-source-agreements
  if ($LASTEXITCODE -ne 0) { Fail 'Tailscale installation failed.' }
  $tailscale = Resolve-Tailscale
}
if (-not $tailscale) { Fail 'Tailscale installed but tailscale.exe was not found.' }

$statusRaw = & $tailscale status --json 2>$null
$status = $null
if ($LASTEXITCODE -eq 0 -and $statusRaw) {
  try { $status = ([string]::Join([Environment]::NewLine, $statusRaw) | ConvertFrom-Json) } catch {}
}

if (-not $status -or $status.BackendState -ne 'Running') {
  Write-Host 'Tailscale needs account authentication. Complete the browser sign-in opened by the next command.' -ForegroundColor Yellow
  & $tailscale up
  if ($LASTEXITCODE -ne 0) { Fail 'Tailscale login/up did not complete.' }
  $statusRaw = & $tailscale status --json
  if ($LASTEXITCODE -ne 0) { Fail 'Tailscale status failed after login.' }
  $status = ([string]::Join([Environment]::NewLine, $statusRaw) | ConvertFrom-Json)
}

Write-Host 'Configuring private Tailscale Serve for Senior. This does NOT enable Funnel/public internet access.'
$appTarget = "http://127.0.0.1:$Port"
$apiTarget = 'http://127.0.0.1:3001'

# OpenBot's local Vite runtime serves the UI on 3010 and intentionally announces SERVER_PORT=3001
# for WebSockets. The phone therefore needs private HTTPS/TLS termination for both ports.
& $tailscale serve --https=443 --bg $appTarget
if ($LASTEXITCODE -ne 0) {
  Fail 'Tailscale Serve for the Senior UI was not enabled. If a Tailscale HTTPS consent page was shown, approve it and rerun this script.'
}
& $tailscale serve --https=3001 --bg $apiTarget
if ($LASTEXITCODE -ne 0) {
  Fail 'Tailscale Serve for Senior WebSockets was not enabled on private port 3001.'
}

$serveText = [string]::Join([Environment]::NewLine, (& $tailscale serve status))
if ($LASTEXITCODE -ne 0) { Fail 'Tailscale Serve status could not be verified.' }
if ($serveText -notmatch ':3001') {
  Fail 'Tailscale Serve does not show the required private 3001 WebSocket listener.'
}

$statusRaw = & $tailscale status --json
$status = ([string]::Join([Environment]::NewLine, $statusRaw) | ConvertFrom-Json)
$dns = [string]$status.Self.DNSName
$dns = $dns.TrimEnd('.')
if (-not $dns) { Fail 'Tailscale is running but this device has no MagicDNS name to report.' }

Write-Host ""
Write-Host "SENIOR PHONE ACCESS = CONFIGURED" -ForegroundColor Green
Write-Host "Private URL: https://$dns/"
Write-Host "Private WebSocket route: https://${dns}:3001/"
Write-Host 'Install Tailscale on the phone, sign into the same tailnet, then open the private URL above.'
Write-Host 'Both listeners are Tailscale Serve routes inside the tailnet; Funnel/public exposure is not enabled.'
