param(
  [string]$UsbRoot = 'D:\SENIOR_AI',
  [string]$Repo = 'C:\Users\Duke1\OpenBot',
  [switch]$InstallOnly
)

$ErrorActionPreference = 'Stop'
$Model = 'maternion/spark-x2.5:4b'
$EnvFile = Join-Path $Repo '.env'

function Step($m) { Write-Host ""; Write-Host "== $m ==" -ForegroundColor Cyan }
function Fail($m) { throw $m }

Step "VERIFY KING + OPENBOT"
if (-not (Test-Path $UsbRoot)) { Fail "KING root not found: $UsbRoot" }
if (-not (Test-Path (Join-Path $UsbRoot 'models'))) { Fail "KING model directory missing." }
if (-not (Test-Path $Repo)) { Fail "OpenBot repo not found: $Repo" }
if (-not (Test-Path $EnvFile)) { Fail "OpenBot .env not found: $EnvFile" }

Step "LOCK OPENBOT TO LOCAL SPARK"
$backup = "$EnvFile.pre-king-stage2.$(Get-Date -Format 'yyyyMMdd-HHmmss').bak"
Copy-Item $EnvFile $backup -Force

function Set-DotEnv([string]$Key, [string]$Value) {
  $text = [IO.File]::ReadAllText($EnvFile)
  $pattern = '(?m)^' + [regex]::Escape($Key) + '=.*$'
  $line = "$Key=$Value"
  if ([regex]::IsMatch($text, $pattern)) {
    $text = [regex]::Replace($text, $pattern, [System.Text.RegularExpressions.MatchEvaluator]{ param($m) $line })
  } else {
    if ($text.Length -gt 0 -and -not $text.EndsWith([Environment]::NewLine)) {
      $text += [Environment]::NewLine
    }
    $text += $line + [Environment]::NewLine
  }
  [IO.File]::WriteAllText($EnvFile, $text, [Text.UTF8Encoding]::new($false))
}

Set-DotEnv 'OPENAI_BASE_URL' 'http://127.0.0.1:11434/v1'
Set-DotEnv 'OPENAI_CONTAINER_BASE_URL' 'http://host.docker.internal:11434/v1'
Set-DotEnv 'OPENAI_API_KEY' 'ollama-local'
Set-DotEnv 'BOT_PROVIDER' 'openai'
Set-DotEnv 'BOT_MODEL' $Model
Set-DotEnv 'AGENT_BOT_MODEL' $Model
Write-Host "OpenBot routing pinned to KING Spark."
Write-Host "Backup: $backup"

Step "SYNC SENIOR CONFIG TO KING"
$seniorSource = Join-Path $Repo 'examples\senior'
$seniorDest = Join-Path $UsbRoot 'senior\config'
New-Item -ItemType Directory -Force -Path $seniorDest | Out-Null
& robocopy $seniorSource $seniorDest /E /R:2 /W:2 /NFL /NDL /NP | Out-Null
if ($LASTEXITCODE -gt 7) { Fail "Senior config sync failed. Robocopy exit code $LASTEXITCODE." }

Step "INSTALL KING FULL-STACK RUNTIME"
$runtimeDir = Join-Path $UsbRoot 'runtime'
$logsDir = Join-Path $UsbRoot 'logs'
New-Item -ItemType Directory -Force -Path $runtimeDir,$logsDir | Out-Null

$runtime = @'
param([switch]$NoBrowser)

$ErrorActionPreference = 'Stop'
$UsbRoot = Split-Path -Parent $PSScriptRoot
$Repo = 'C:\Users\Duke1\OpenBot'
$Model = 'maternion/spark-x2.5:4b'
$ModelDir = Join-Path $UsbRoot 'models'
$Logs = Join-Path $UsbRoot 'logs'

function Step($m) { Write-Host ""; Write-Host "== $m ==" -ForegroundColor Cyan }
function Fail($m) { throw $m }

function To-BashPath([string]$Path) {
  $full = [IO.Path]::GetFullPath($Path)
  if ($full -match '^([A-Za-z]):\\(.*)$') {
    $drive = $matches[1].ToLower()
    $rest = $matches[2].Replace('\','/')
    return "/$drive/$rest"
  }
  return $full.Replace('\','/')
}

function Test-Docker {
  try {
    & docker info *> $null
    return ($LASTEXITCODE -eq 0)
  } catch {
    return $false
  }
}

Step "START KING OLLAMA"
if (-not (Test-Path $ModelDir)) { Fail "KING model store is missing: $ModelDir" }
$ollama = (Get-Command ollama.exe -ErrorAction SilentlyContinue).Source
if (-not $ollama) {
  $candidate = "$env:LOCALAPPDATA\Programs\Ollama\ollama.exe"
  if (Test-Path $candidate) { $ollama = $candidate }
}
if (-not $ollama) { Fail "Ollama is not installed on this Windows host." }

$env:OLLAMA_MODELS = $ModelDir
$env:OLLAMA_HOST = '127.0.0.1:11434'
Get-Process ollama -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2
Start-Process -FilePath $ollama -ArgumentList 'serve' -WindowStyle Hidden -RedirectStandardOutput (Join-Path $Logs 'ollama.log') -RedirectStandardError (Join-Path $Logs 'ollama-error.log')

$ready = $false
1..45 | ForEach-Object {
  if (-not $ready) {
    try {
      $tags = Invoke-RestMethod -Uri 'http://127.0.0.1:11434/api/tags' -TimeoutSec 2
      $ready = $true
    } catch {
      Start-Sleep -Seconds 1
    }
  }
}
if (-not $ready) { Fail "KING Ollama did not start." }
if (-not ($tags.models.name -contains $Model)) { Fail "KING Ollama started but Spark Q4 is missing." }
Write-Host "KING Ollama: READY" -ForegroundColor Green

Step "START DOCKER DESKTOP"
if (-not (Get-Command docker.exe -ErrorAction SilentlyContinue)) { Fail "Docker CLI is not installed on this host." }
if (-not (Test-Docker)) {
  $dockerDesktop = 'C:\Program Files\Docker\Docker\Docker Desktop.exe'
  if (-not (Test-Path $dockerDesktop)) { Fail "Docker Desktop is not running and its standard launcher was not found." }
  Start-Process $dockerDesktop
  1..180 | ForEach-Object {
    if (-not (Test-Docker)) { Start-Sleep -Seconds 1 }
  }
}
if (-not (Test-Docker)) { Fail "Docker Desktop did not become ready." }
Write-Host "Docker Desktop: READY" -ForegroundColor Green

Step "START OPENBOT"
$bashCandidates = @(
  'C:\Program Files\Git\bin\bash.exe',
  'C:\Program Files\Git\usr\bin\bash.exe',
  "$env:LOCALAPPDATA\Programs\Git\bin\bash.exe"
)
$bash = $bashCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $bash) { Fail "Git Bash was not found." }
if (-not (Test-Path $Repo)) { Fail "OpenBot repo is missing: $Repo" }

$repoBash = To-BashPath $Repo
& $bash -lc "cd '$repoBash' && bash scripts/start.sh"
if ($LASTEXITCODE -ne 0) { Fail "OpenBot startup failed with exit code $LASTEXITCODE." }

Step "VERIFY FULL LOCAL ROUTE"
& $bash -lc "cd '$repoBash' && bash scripts/verify-king-stage2.sh"
if ($LASTEXITCODE -ne 0) { Fail "KING Stage 2 verification failed with exit code $LASTEXITCODE." }

Write-Host ""
Write-Host "SENIOR FULL STACK = READY" -ForegroundColor Green
Write-Host "Senior:  http://localhost:3010/bot"
Write-Host "OpenBot: http://localhost:3010"
Write-Host "Model:   $Model"
Write-Host "Models:  $ModelDir"

if (-not $NoBrowser) {
  Start-Process 'http://localhost:3010/bot'
}
'@

$runtimePath = Join-Path $runtimeDir 'start-senior.ps1'
[IO.File]::WriteAllText($runtimePath, $runtime, [Text.UTF8Encoding]::new($false))

$cmd = @'
@echo off
title SENIOR AI - KING
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0runtime\start-senior.ps1"
if errorlevel 1 (
  echo.
  echo SENIOR START FAILED
  pause
)
'@
$launcher = Join-Path $UsbRoot 'START-SENIOR.cmd'
[IO.File]::WriteAllText($launcher, $cmd, [Text.ASCIIEncoding]::new())

Write-Host "Launcher installed: $launcher" -ForegroundColor Green
Write-Host "Runtime installed:  $runtimePath"

if (-not $InstallOnly) {
  Step "RUN KING STAGE 2 NOW"
  # The tenant package is persistent. Force the native API server to reload once during setup so
  # revised Senior/agent definitions are synchronized without deleting conversations or volumes.
  $previousForceReload = $env:OPENBOT_FORCE_RELOAD
  $env:OPENBOT_FORCE_RELOAD = 'true'
  try {
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $runtimePath -NoBrowser
    if ($LASTEXITCODE -ne 0) { Fail "KING Stage 2 runtime failed." }
  } finally {
    if ($null -eq $previousForceReload) {
      Remove-Item Env:OPENBOT_FORCE_RELOAD -ErrorAction SilentlyContinue
    } else {
      $env:OPENBOT_FORCE_RELOAD = $previousForceReload
    }
  }
}

Write-Host ""
Write-Host "KING STAGE 2 INSTALL = PASS" -ForegroundColor Green
Write-Host "One-click launcher: $launcher"
