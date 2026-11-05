# Resolve built-in modules from the running host, even with an empty inherited
# PSModulePath or disabled module auto-loading (including GUI runspaces).
foreach($ac8Module in @('Microsoft.PowerShell.Management','Microsoft.PowerShell.Utility')){
 $ac8ModulePath=[IO.Path]::Combine($PSHOME,'Modules',$ac8Module,($ac8Module+'.psd1'))
 Import-Module -Name $ac8ModulePath -ErrorAction Stop
}
function Enter-AC8Operation([string]$GameRoot,[ValidateRange(0,60000)][int]$WaitMilliseconds=0){
 $canonical=[IO.Path]::GetFullPath($GameRoot).TrimEnd('\','/').ToUpperInvariant()
 $sha=[Security.Cryptography.SHA256]::Create()
 try{$key=[BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($canonical))).Replace('-','')}finally{$sha.Dispose()}
 $mutex=New-Object Threading.Mutex($false,('Local\AC8IntegratedSession-'+$key))
 $owned=$false
 try{
  try{
   $owned=$mutex.WaitOne(0)
   if(!$owned -and $WaitMilliseconds -gt 0){
    Write-Host '上次会话正在恢复或整理记录，等待完成后继续（最多 60 秒）……'
    $owned=$mutex.WaitOne($WaitMilliseconds)
   }
  }catch [Threading.AbandonedMutexException]{$owned=$true}
  if(!$owned){
   $failure=New-Object InvalidOperationException('另一个 AC8 会话仍在启动、恢复或整理记录。')
   $failure.Data['AC8Hint']='请稍候再试。本次没有重复启动游戏；不需要修改路径或权限，也不要删除活动会话记录。'
   $failure.Data['AC8Code']='SESSION_BUSY';throw $failure
  }
  return $mutex
 }catch{$mutex.Dispose();throw}
}
function Exit-AC8Operation($Mutex){if($Mutex){try{$Mutex.ReleaseMutex()}finally{$Mutex.Dispose()}}}
# Idempotent when imported through both Install-Common and Cleanup-Core.
if(!(Test-Path Function:\Get-AC8FileHash)){
 function Get-AC8FileHash {
  param([Parameter(Mandatory=$true)][string]$LiteralPath,[ValidateSet('SHA256')][string]$Algorithm='SHA256')
  $path=$ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($LiteralPath)
  $stream=$null;$sha=$null
  try{
   $stream=[IO.File]::Open($path,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
   $sha=[Security.Cryptography.SHA256]::Create()
   $digest=[BitConverter]::ToString($sha.ComputeHash($stream)).Replace('-','')
   return [pscustomobject]@{Algorithm='SHA256';Hash=$digest;Path=$path}
  }finally{if($sha){$sha.Dispose()};if($stream){$stream.Dispose()}}
 }
}
