param(
  [string]$UsbRoot = 'D:\SENIOR_AI'
)

$ErrorActionPreference = 'Stop'
$Model = 'maternion/spark-x2.5:4b'
$Launcher = Join-Path $UsbRoot 'START-SENIOR.cmd'
$Dest = Join-Path $UsbRoot 'models'

function Step($m) { Write-Host ""; Write-Host "== $m ==" -ForegroundColor Cyan }
function Fail($m) { throw $m }

Step "VERIFY KING FILES"
if (-not (Test-Path $Launcher)) { Fail "Missing launcher: $Launcher" }
if (-not (Test-Path (Join-Path $Dest 'blobs'))) { Fail "KING model store is missing blobs." }
if (-not (Test-Path (Join-Path $Dest 'manifests'))) { Fail "KING model store is missing manifests." }

Step "COLD STOP OLLAMA"
Get-Process ollama -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2

Step "START SENIOR FROM KING"
Start-Process -FilePath $Launcher -WorkingDirectory $UsbRoot
$ready = $false
1..45 | ForEach-Object {
  if (-not $ready) {
    try {
      Invoke-RestMethod -Uri 'http://127.0.0.1:11434/api/tags' -TimeoutSec 2 | Out-Null
      $ready = $true
    } catch { Start-Sleep -Seconds 1 }
  }
}
if (-not $ready) { Fail "Ollama did not come back after starting $Launcher." }

Step "VERIFY OLLAMA PROCESS ENVIRONMENT"
# The launcher sets OLLAMA_MODELS for the child process. Confirm behavior through the models visible
# from the freshly started server rather than trusting the parent shell environment.
$tags = Invoke-RestMethod -Uri 'http://127.0.0.1:11434/api/tags' -TimeoutSec 5
if (-not ($tags.models.name -contains $Model)) {
  Fail "Fresh KING-started Ollama does not see $Model."
}

Step "VERIFY SPARK AFTER COLD START"
$body = @{
  model = $Model
  messages = @(@{ role='user'; content='Reply briefly with: KING COLD START PASS' })
  stream = $false
  think = $false
  options = @{ num_ctx=8192; num_predict=96 }
} | ConvertTo-Json -Depth 6

$response = Invoke-RestMethod -Uri 'http://127.0.0.1:11434/api/chat' -Method Post -ContentType 'application/json' -Body $body -TimeoutSec 180
$content = [string]$response.message.content
if (-not $response.done -or [string]::IsNullOrWhiteSpace($content)) {
  $response | ConvertTo-Json -Depth 8 | Set-Content (Join-Path $UsbRoot 'logs\king-cold-start-response.json') -Encoding UTF8
  Fail "Cold-start Spark inference failed. Diagnostic saved under KING logs."
}

Write-Host ""
Write-Host "KING COLD START = PASS" -ForegroundColor Green
Write-Host ("Spark said: " + $content.Trim())
Write-Host "Model store: $Dest"
Write-Host "Launcher: $Launcher"
Write-Host ""
Write-Host "Do NOT delete the legacy model store yet; report this PASS first."
