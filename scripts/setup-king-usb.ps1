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
# Idempotent: once KING has an Ollama model store, do not re-copy multi-GB blobs.
# The required Q4 model is verified below and pulled directly to KING only if missing.
$destHasStore = (Test-Path "$dest\blobs") -and (Test-Path "$dest\manifests") -and ((Get-ChildItem "$dest\blobs" -File -ErrorAction SilentlyContinue | Measure-Object).Count -gt 0)
if ($destHasStore) {
  Write-Host "KING model store is already populated; skipping bulk model copy."
} elseif ((Test-Path $source) -and ((Resolve-Path $source).Path -ne (Resolve-Path $dest).Path)) {
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
  messages = @(@{ role='user'; content='Reply briefly with: KING SPARK READY' })
  stream = $false
  think = $false
  options = @{ num_ctx=8192; num_predict=96 }
} | ConvertTo-Json -Depth 6
$response = Invoke-RestMethod -Uri 'http://127.0.0.1:11434/api/chat' -Method Post -ContentType 'application/json' -Body $body -TimeoutSec 180

# Thinking-capable models can spend a short token budget entirely in message.thinking.
# Disable thinking for this acceptance test and require a completed user-visible answer.
$content = [string]$response.message.content
if (-not $response.done -or [string]::IsNullOrWhiteSpace($content)) {
  $thinkingLength = ([string]$response.message.thinking).Length
  Write-Host ("Diagnostic: done={0}; done_reason={1}; eval_count={2}; thinking_chars={3}" -f $response.done, $response.done_reason, $response.eval_count, $thinkingLength)
  $response | ConvertTo-Json -Depth 8 | Set-Content "$UsbRoot\logs\king-spark-last-response.json" -Encoding UTF8
  Fail "Spark on KING completed without a user-visible answer. Diagnostic saved to logs\king-spark-last-response.json."
}
Write-Host "Spark inference from KING: PASS" -ForegroundColor Green
Write-Host ("Spark said: " + $content.Trim())

Step "REMOVE UNUSABLE 8.2GB BF16 COPY FROM KING"
$modelList = (& $ollama list | Out-String)
if ($modelList -match [regex]::Escape('SparkLLM/Spark-X2.5-4B')) {
  & $ollama rm $HeavyModel | Out-Host
} else {
  Write-Host "No SparkLLM 8.2GB BF16 model registered in the KING store."
}

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
