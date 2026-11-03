param([ValidateSet('Setup','Start','Session','Cleanup','Recover','Features','Analyze')][string]$Action,[switch]$CheckOnly,[switch]$SessionWorker)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'Install-Common.ps1')
# The session monitor must outlive the visible Steam bridge console.
if($Action -eq 'Session' -and !$CheckOnly -and !$SessionWorker){
 $logs=Join-Path $PSScriptRoot 'diagnostics'
 New-Item -ItemType Directory -Path $logs -Force | Out-Null
 $prefix=Join-Path $logs ('session-monitor-'+(Get-Date -Format 'yyyyMMdd-HHmmss')+'-'+[guid]::NewGuid().ToString('N').Substring(0,8))
 $arguments='-NoProfile -ExecutionPolicy Bypass -File "'+$PSCommandPath+'" -Action Session -SessionWorker'
 $worker=Start-Process -FilePath (Join-Path $PSHOME 'powershell.exe') -ArgumentList $arguments -WindowStyle Hidden -RedirectStandardOutput ($prefix+'.log') -RedirectStandardError ($prefix+'.error.log') -PassThru
 Write-Host 'MOD 会话监控已启动，下面实时显示启动与退出日志。'
 Write-Host ('日志位置：'+$prefix+'.log')
 $readers=New-Object Collections.Generic.List[IO.StreamReader]
 try{
  foreach($path in @(($prefix+'.log'),($prefix+'.error.log'))){
   $stream=New-Object IO.FileStream($path,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::ReadWrite)
   $readers.Add((New-Object IO.StreamReader($stream,[Text.Encoding]::Default,$true)))
  }
  do{
   $finished=$worker.WaitForExit(200)
   foreach($reader in $readers){while(!$reader.EndOfStream){Write-Host $reader.ReadLine()}}
  }while(!$finished)
  # Flush redirected output after process termination before the final drain.
  $worker.WaitForExit()
  foreach($reader in $readers){while(!$reader.EndOfStream){Write-Host $reader.ReadLine()}}
 }finally{foreach($reader in $readers){$reader.Dispose()}}
 exit $worker.ExitCode
}

try {
 if($CheckOnly -and $Action -ne 'Session'){throw 'CheckOnly is supported only for Session.'}
 switch($Action){
  'Setup' {& (Join-Path $PSScriptRoot 'Setup.ps1')}
  'Start' {& (Join-Path $PSScriptRoot 'Launch-AC8-via-Steam.ps1')}
  'Session' {& (Join-Path $PSScriptRoot 'Start-ModSession.ps1') -CheckOnly:$CheckOnly}
  'Cleanup' {& (Join-Path $PSScriptRoot 'Launch-Offline.ps1') -CleanupOnly}
  'Recover' {& (Join-Path $PSScriptRoot 'Recover-Cleanup.ps1') -Interactive}
  'Features' {& (Join-Path $PSScriptRoot 'Choose-Features.ps1')}
  'Analyze' {& (Join-Path $PSScriptRoot 'Analyze-Latest.ps1')}
 }
 exit 0
}catch{if($CheckOnly){Write-Host ('CHECK FAILED: '+$_.Exception.Message)}else{Show-AC8Problem $_ $PSScriptRoot $Action};exit 1}
