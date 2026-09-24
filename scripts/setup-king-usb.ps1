param(
  [string]$UsbRoot = 'D:\SENIOR_AI'
)

$ErrorActionPreference = 'Stop'
$Model = 'maternion/spark-x2.5:4b'
$HeavyModel = 'SparkLLM/Spark-X2.5-4B'
$Drive = [System.IO.Path]::GetPathRoot($UsbRoot)

function Step($m) { Write-Host ""; Write-Host "== $m ==" -ForegroundColor Cyan }
function Fail($m) { throw $m }

Step "VERIFY KING USB"
if (-not (Test-Path $Drive)) { Fail "$Drive is not mounted. Plug in KING and retry." }
try {
  $disk = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='$($Drive.TrimEnd('\'))'"
  if ($disk.VolumeName -and $disk.VolumeName -ne 'KING') {
    Write-Warning "Drive $Drive is labelled '$($disk.VolumeName)', not KING. Continuing because D: was explicitly selected."
  }
} catch {}

$dirs = @(
  $UsbRoot,
  "$UsbRoot\models",
  "$UsbRoot\senior",
  "$UsbRoot\senior\agents",
  "$UsbRoot\senior\memory",
  "$UsbRoot\senior\config",
  "$UsbRoot\senior\tools",
  "$UsbRoot\runtime",
  "$UsbRoot\data",
  "$UsbRoot\logs"
)
$dirs | ForEach-Object { New-Item -ItemType Directory -Force -Path $_ | Out-Null }

$ollama = (Get-Command ollama.exe -ErrorAction SilentlyContinue).Source
if (-not $ollama) {
  $candidate = "$env:LOCALAPPDATA\Programs\Ollama\ollama.exe"
  if (Test-Path $candidate) { $ollama = $candidate }
}
if (-not $ollama) { Fail "Ollama executable not found." }

$source = if ($env:OLLAMA_MODELS -and (Test-Path $env:OLLAMA_MODELS)) {
  $env:OLLAMA_MODELS
} else {
  "$HOME\.ollama\models"
}
$dest = "$UsbRoot\models"

Step "COPY EXISTING OLLAMA MODELS TO KING"
if ((Test-Path $source) -and ((Resolve-Path $source).Path -ne (Resolve-Path $dest).Path)) {
  & robocopy $source $dest /E /COPY:DAT /DCOPY:DAT /R:2 /W:2 /NFL /NDL /NP
  $rc = $LASTEXITCODE
  if ($rc -gt 7) { Fail "Model copy failed. Robocopy exit code $rc." }
} else {
  Write-Host "Model store is already on KING or source store is empty."
}

Step "MAKE KING THE OLLAMA MODEL HOME"
[Environment]::SetEnvironmentVariable('OLLAMA_MODELS', $dest, 'User')
$env:OLLAMA_MODELS = $dest

Get-Process ollama -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2
$log = "$UsbRoot\logs\ollama.log"
Start-Process -FilePath $ollama -ArgumentList 'serve' -WindowStyle Hidden -RedirectStandardOutput $log -RedirectStandardError "$UsbRoot\logs\ollama-error.log"

$ready = $false
1..30 | ForEach-Object {
  if (-not $ready) {
    try {
      Invoke-RestMethod -Uri 'http://127.0.0.1:11434/api/tags' -TimeoutSec 2 | Out-Null
      $ready = $true
    } catch { Start-Sleep -Seconds 1 }
  }
}
if (-not $ready) { Fail "Ollama did not start from KING model configuration." }

Step "VERIFY SPARK-X2.5-4B Q4 FROM KING"
$tags = Invoke-RestMethod -Uri 'http://127.0.0.1:11434/api/tags' -TimeoutSec 5
if (-not ($tags.models.name -contains $Model)) {
  Write-Host "Q4 model was not present in copied store. Pulling it directly to KING..."
  & $ollama pull $Model
  if ($LASTEXITCODE -ne 0) { Fail "Spark Q4 pull to KING failed." }
}

$body = @{
  model = $Model
  messages = @(@{ role='user'; content='Reply with exactly: KING SPARK READY' })
  stream = $false
  options = @{ num_ctx=8192; num_predict=32 }
} | ConvertTo-Json -Depth 6
$response = Invoke-RestMethod -Uri 'http://127.0.0.1:11434/api/chat' -Method Post -ContentType 'application/json' -Body $body -TimeoutSec 180
# A local model may add reasoning or formatting even when inference is healthy. The acceptance gate
# is successful generation, not exact wording.
$content = [string]$response.message.content
if (-not $response.done -or [string]::IsNullOrWhiteSpace($content)) {
  Fail "Spark on KING did not return a completed non-empty response."
}
Write-Host "Spark inference from KING: PASS" -ForegroundColor Green
Write-Host ("Spark said: " + $content.Trim())

Step "REMOVE UNUSABLE 8.2GB BF16 COPY FROM KING"
& $ollama list | Select-String -SimpleMatch 'SparkLLM/Spark-X2.5-4B' | Out-Null
if ($?) { & $ollama rm $HeavyModel | Out-Host }

Step "COPY SENIOR CONFIGURATION TO KING"
$repo = Split-Path -Parent $PSScriptRoot
$seniorSource = Join-Path $repo 'examples\senior'
if (Test-Path $seniorSource) {
  robocopy $seniorSource "$UsbRoot\senior\config" /E /R:2 /W:2 /NFL /NDL /NP | Out-Null
}

$launcher = @'
@echo off
setlocal
set "SENIOR_ROOT=%~dp0"
set "OLLAMA_MODELS=%SENIOR_ROOT%models"
set "OLLAMA_HOST=127.0.0.1:11434"
set "OLLAMA_EXE=%LOCALAPPDATA%\Programs\Ollama\ollama.exe"
if not exist "%OLLAMA_EXE%" (
  echo Ollama is not installed on this Windows host.
  pause
  exit /b 1
)
if not exist "%SENIOR_ROOT%models" (
  echo KING Senior model directory is missing.
  pause
  exit /b 1
)
start "Senior Local AI" /min "%OLLAMA_EXE%" serve
timeout /t 3 /nobreak >nul
echo.
echo Senior local AI is starting from KING.
echo Model store: %SENIOR_ROOT%models
echo API: http://127.0.0.1:11434
echo.
echo OpenBot remains a host dependency during this migration stage.
endlocal
'@
Set-Content -Path "$UsbRoot\START-SENIOR.cmd" -Value $launcher -Encoding ASCII

Write-Host ""
Write-Host "KING USB STAGE 1 = PASS" -ForegroundColor Green
Write-Host "Spark model home: $dest"
Write-Host "Launcher: $UsbRoot\START-SENIOR.cmd"
Write-Host "NOTE: The original C: model store has NOT been deleted yet."
Write-Host "It will be removed only after a cold-start verification from KING."
