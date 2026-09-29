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
$target = "http://127.0.0.1:$Port"
& $tailscale serve --bg $target
if ($LASTEXITCODE -ne 0) {
  Fail 'Tailscale Serve was not enabled. If a Tailscale HTTPS consent page was shown, approve it and rerun this script.'
}

$serve = & $tailscale serve status --json
if ($LASTEXITCODE -ne 0) { Fail 'Tailscale Serve status could not be verified.' }

$statusRaw = & $tailscale status --json
$status = ([string]::Join([Environment]::NewLine, $statusRaw) | ConvertFrom-Json)
$dns = [string]$status.Self.DNSName
$dns = $dns.TrimEnd('.')
if (-not $dns) { Fail 'Tailscale is running but this device has no MagicDNS name to report.' }

Write-Host ""
Write-Host "SENIOR PHONE ACCESS = CONFIGURED" -ForegroundColor Green
Write-Host "Private URL: https://$dns/"
Write-Host 'Install Tailscale on the phone, sign into the same tailnet, then open that private URL.'
