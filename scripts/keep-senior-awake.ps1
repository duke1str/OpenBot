param(
  [string]$PidFile = ''
)

$ErrorActionPreference = 'Stop'
if (-not $PidFile) {
  $repo = Split-Path -Parent $PSScriptRoot
  $PidFile = Join-Path $repo '.logs\senior-awake.pid'
}

$mutex = New-Object System.Threading.Mutex($false, 'OpenBotSeniorAwake')
$owned = $false

try {
  try {
    $owned = $mutex.WaitOne(0, $false)
  } catch [System.Threading.AbandonedMutexException] {
    $owned = $true
  }
  if (-not $owned) { exit 0 }

  $signature = @'
using System;
using System.Runtime.InteropServices;
public static class SeniorPower {
  [DllImport("kernel32.dll")]
  public static extern uint SetThreadExecutionState(uint esFlags);
}
'@
  Add-Type -TypeDefinition $signature

  $dir = Split-Path -Parent $PidFile
  New-Item -ItemType Directory -Force -Path $dir | Out-Null
  [IO.File]::WriteAllText($PidFile, [string]$PID, [Text.UTF8Encoding]::new($false))

  $ES_CONTINUOUS = [uint32]0x80000000
  $ES_SYSTEM_REQUIRED = [uint32]0x00000001
  $flags = $ES_CONTINUOUS -bor $ES_SYSTEM_REQUIRED

  while ($true) {
    $result = [SeniorPower]::SetThreadExecutionState($flags)
    if ($result -eq 0) { throw 'Windows refused the Senior keep-awake request.' }
    Start-Sleep -Seconds 45
  }
}
finally {
  if ('SeniorPower' -as [type]) {
    [void][SeniorPower]::SetThreadExecutionState([uint32]0x80000000)
  }
  Remove-Item $PidFile -Force -ErrorAction SilentlyContinue
  if ($owned) {
    try { $mutex.ReleaseMutex() } catch {}
  }
  $mutex.Dispose()
}
