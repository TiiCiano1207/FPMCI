. (Join-Path $PSScriptRoot 'Cleanup-Core.ps1')

function Read-AC8BackupRecord([string]$Path) {
 if(!(Test-Path -LiteralPath $Path -PathType Leaf)){return $null}
 try {$record=Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json;foreach($item in $record){$item}}
 catch {Write-Warning ('Unreadable backup metadata, treated as unfinished: '+$Path);return $null}
}

# Call under Enter-AC8Operation. Only MOD-generated direct children are eligible.
# Logical sizes deliberately overcount hard links for a stable, conservative cap.
function Get-AC8BackupGroups([string]$PackageRoot) {
 $package=[IO.Path]::GetFullPath($PackageRoot).TrimEnd('\','/')
 Assert-AC8NoLinks $package
 $activePath=Join-Path $package 'active-session.json'
 $active=$null;$activeResults=''
 if(Test-Path -LiteralPath $activePath){
  Assert-AC8NoLinks $activePath
  # Damaged active records stop maintenance rather than silently losing protection.
  $active=Get-Content -LiteralPath $activePath -Raw -Encoding UTF8 | ConvertFrom-Json
  $activeResults=[IO.Path]::GetFullPath([string]$active.Results)
 }
 $groups=@{};$sessionRoot=Join-Path $package 'sessions'
 foreach($folder in @('sessions','cleanup-backups')){
  $base=Join-Path $package $folder
  if(!(Test-Path -LiteralPath $base)){continue}
  Assert-AC8NoLinks $base
  foreach($dir in Get-ChildItem -LiteralPath $base -Directory -Force){
   $pattern=if($folder -eq 'sessions'){'^\d{8}-\d{6}-[a-f0-9]{8}$'}else{'^(\d{8}-\d{6}-[a-f0-9]{32}|completed-[a-f0-9]{32})$'}
   if($dir.Name -notmatch $pattern){continue}
   Assert-AC8NoLinks $dir.FullName -Tree
   if($folder -eq 'sessions'){
    $status=Read-AC8BackupRecord (Join-Path $dir.FullName 'session-status.json')
    $monitor=Read-AC8BackupRecord (Join-Path $dir.FullName 'monitor-status.json')
    $complete=($status.Status -eq 'complete' -or (!(Test-Path -LiteralPath (Join-Path $dir.FullName 'session-status.json')) -and (Test-Path -LiteralPath (Join-Path $dir.FullName 'save-hashes-after.json'))))
    $protected=$dir.FullName -ieq $activeResults
    if(!$status -and $monitor.MonitorPID -and $monitor.Time){
     $process=Get-Process -Id $monitor.MonitorPID -ErrorAction SilentlyContinue
     if($process -and $process.StartTime.ToUniversalTime() -le [DateTime]::Parse($monitor.Time).ToUniversalTime()){$protected=$true}
    }
    $groups[$dir.FullName]=[pscustomobject]@{Category=$(if($complete){'normal'}else{'abnormal'});Paths=@($dir.FullName);Order=$dir.Name;Protected=$protected;Stage=[string]$monitor.Stage}
   }
  }
 }
 $backupRoot=Join-Path $package 'cleanup-backups'
 if(Test-Path -LiteralPath $backupRoot){
  foreach($dir in Get-ChildItem -LiteralPath $backupRoot -Directory -Force){
   if($dir.Name -notmatch '^(\d{8}-\d{6}-[a-f0-9]{32}|completed-[a-f0-9]{32})$'){continue}
   $state=Read-AC8BackupRecord (Join-Path $dir.FullName 'completed-session.json')
   $report=Read-AC8BackupRecord (Join-Path $dir.FullName 'cleanup-report.json')
   $session=''
   if($state.Results){$session=[IO.Path]::GetFullPath([string]$state.Results)}
   if($session -and (Split-Path $session -Parent) -ieq $sessionRoot -and $groups.ContainsKey($session)){
    $group=$groups[$session];$group.Paths+= $dir.FullName
    if($report.Status -ne 'complete'){$group.Category='abnormal'}
   }else{
    $groups[$dir.FullName]=[pscustomobject]@{Category='abnormal';Paths=@($dir.FullName);Order=$dir.CreationTime.ToString('yyyyMMdd-HHmmss')+'-'+$dir.Name;Protected=([bool]$active -and (!$state -or $session -ieq $activeResults -or $state.Id -eq $active.Id));Stage=[string]$report.Status}
   }
  }
 }
 # Rollback copies are maintained only when no recorded session is active.
 if(!$active){
  foreach($spec in @(
   @('settings-backups','settings','^\d{8}-\d{6}-\d{3}-[a-f0-9]{6}$'),
   @('resource-backups','resources','^\d{8}-\d{6}-[a-f0-9]{8}$'),
   @('update-backups','updates','^(compatibility-[0-9.]+|fpmci-ui-[0-9.]+|fpmci-fix-[0-9.]+)-\d{8}-\d{6}-\d{3}-[a-f0-9]{6}$'),
   @('diagnostics','diagnostics','^workbench-\d{8}-\d{6}-[a-f0-9]{8}$'))){
   $base=Join-Path $package $spec[0]
   if(!(Test-Path -LiteralPath $base)){continue}
   Assert-AC8NoLinks $base
   foreach($dir in Get-ChildItem -LiteralPath $base -Directory -Force){
    if($dir.Name -notmatch $spec[2]){continue}
    Assert-AC8NoLinks $dir.FullName -Tree
    $groups[$dir.FullName]=[pscustomobject]@{Category=$spec[1];Paths=@($dir.FullName);Order=$dir.CreationTime.ToString('yyyyMMdd-HHmmss')+'-'+$dir.Name;Protected=$false;Stage=''}
   }
  }
  $logs=Join-Path $package 'diagnostics'
  if(Test-Path -LiteralPath $logs){
   Assert-AC8NoLinks $logs
   foreach($file in Get-ChildItem -LiteralPath $logs -File -Force){
    if($file.Name -match '^\d{8}-\d{6}-[a-f0-9]{32}\.txt$'){
     Assert-AC8NoLinks $file.FullName
     $groups[$file.FullName]=[pscustomobject]@{Category='diagnostics';Paths=@($file.FullName);Order=$file.Name;Protected=$false;Stage=''}
     continue
    }
    if($file.Name -notmatch '^(session-monitor-\d{8}-\d{6}-[a-f0-9]{8}|direct-session-\d{8}-\d{6}-[a-f0-9]{6})(\.error)?\.log$'){continue}
    $stem=$Matches[1]
    Assert-AC8NoLinks $file.FullName
    $prefix=Join-Path $logs $stem
    if(!$groups.ContainsKey($prefix)){$groups[$prefix]=[pscustomobject]@{Category='diagnostics';Paths=@();Order=$stem;Protected=($prefix -ieq $env:AC8_MONITOR_LOG_PREFIX);Stage=''}}
    $groups[$prefix].Paths+= $file.FullName
   }
  }
 }
 foreach($group in $groups.Values){
  [long]$bytes=0
  foreach($path in $group.Paths){$bytes+= [long](Get-ChildItem -LiteralPath $path -File -Recurse -Force | Measure-Object Length -Sum).Sum}
  $group | Add-Member NoteProperty Bytes $bytes
  $group
 }
}

function Save-AC8RetentionSummary([string]$PackageRoot,[string]$Category,$Paths,[long]$Bytes,[string]$Stage,[string]$LogFile) {
 $historyPath=Join-Path $PackageRoot 'backup-retention-history.json'
 if(Test-Path -LiteralPath $historyPath){Assert-AC8NoLinks $historyPath}
 $history=@(Read-AC8BackupRecord $historyPath | Where-Object {$null -ne $_})
 $tail=''
 if($LogFile){
  $stream=[IO.File]::OpenRead($LogFile)
  try {
   $buffer=New-Object byte[] ([int][Math]::Min(8192,$stream.Length))
   [void]$stream.Seek(-$buffer.Length,[IO.SeekOrigin]::End)
   $length=$stream.Read($buffer,0,$buffer.Length)
   $tail=[Text.Encoding]::UTF8.GetString($buffer,0,$length)
  }finally{$stream.Dispose()}
 }
 if($Stage.Length -gt 512){$Stage=$Stage.Substring(0,512)}
 $history+= [pscustomobject]@{Time=[DateTime]::UtcNow.ToString('o');Category=$Category;Paths=@($Paths | Select-Object -First 8);PathCount=@($Paths).Count;Bytes=$Bytes;Stage=$Stage;LogTail=$tail}
 Write-AC8Json @($history | Select-Object -Last 20) $historyPath
}

# Retention only: producers and active session files are deliberately unchanged.
# The budget is shared by all known inactive log/CSV copies, including archives.
function Invoke-AC8LogRetention([string]$PackageRoot,$Groups,[long]$MaxBytes=16MB,[switch]$Preview) {
 $payload=Join-Path $PackageRoot 'payload'
 if(Test-Path -LiteralPath $payload){
  Assert-AC8NoLinks $payload -Tree
  $bodyBytes=[long](Get-ChildItem -LiteralPath $payload -File -Recurse -Force | Measure-Object Length -Sum).Sum
  $MaxBytes=[Math]::Min($MaxBytes,$bodyBytes)
 }
 # The bounded removal summaries fit in this reserved MiB.
 $budget=[Math]::Max(0,$MaxBytes-1MB)
 $files=@(foreach($group in $Groups | Where-Object {!$_.Protected}){
  if($group.Category -notin @('normal','abnormal','diagnostics')){continue}
  foreach($path in $group.Paths){
   Get-ChildItem -LiteralPath $path -File -Recurse -Force | Where-Object {
    $group.Category -eq 'diagnostics' -or $_.Extension -in @('.log','.csv','.jsonl','.dmp') -or $_.Name -like 'gaze-state-*.txt'
   }
  }
 })
 [long]$used=0
 foreach($file in $files | Sort-Object @{Expression='LastWriteTimeUtc';Descending=$true},FullName){
  if($used+$file.Length -le $budget){$used+=$file.Length;continue}
  Assert-AC8NoLinks $file.FullName
  if($Preview){Write-Output $file.FullName;continue}
  $logFile=if($file.Extension -in @('.log','.txt')){$file.FullName}else{''}
  Save-AC8RetentionSummary $PackageRoot 'logs' @($file.FullName) $file.Length '' $logFile
  Remove-Item -LiteralPath $file.FullName -Force
  Write-Host ('Removed expired MOD log: '+$file.FullName)
 }
}

function Invoke-AC8BackupRetention {
 param([Parameter(Mandatory=$true)][string]$PackageRoot,[int]$Keep=3,[long]$MaxBytes=1GB,[int]$KeepAbnormal=3,[long]$MaxAbnormalBytes=512MB,[long]$MaxLogBytes=16MB,[switch]$Preview)
 if($Keep -lt 1 -or $KeepAbnormal -lt 1 -or $MaxBytes -lt 1 -or $MaxAbnormalBytes -lt 1 -or $MaxLogBytes -lt 1){throw 'Retention counts and capacities must be positive.'}
 $package=[IO.Path]::GetFullPath($PackageRoot).TrimEnd('\','/')
 $groups=@(Get-AC8BackupGroups $package)
 $limits=@{normal=@($Keep,$MaxBytes);abnormal=@($KeepAbnormal,$MaxAbnormalBytes);settings=@(3,16MB);resources=@(3,64MB);updates=@(3,256MB);diagnostics=@(20,64MB)}
 $allowedParents=@('sessions','cleanup-backups','settings-backups','resource-backups','update-backups','diagnostics' | ForEach-Object {Join-Path $package $_})
 $readOnly=@(if(!$Preview){foreach($group in $groups | Where-Object {$_.Category -in @('normal','abnormal')}){foreach($path in $group.Paths){Get-ChildItem -LiteralPath $path -File -Recurse -Force | Where-Object {$_.IsReadOnly}}}})
 $retained=@($groups | Where-Object {$_.Protected})
 try {
 foreach($category in $limits.Keys){
  $count=0;[long]$used=0
  foreach($group in $groups | Where-Object {$_.Category -eq $category -and !$_.Protected} | Sort-Object Order -Descending){
   if($count -lt $limits[$category][0] -and $used+$group.Bytes -le $limits[$category][1]){$count++;$used+=$group.Bytes;$retained+=$group;continue}
   if(!$Preview){
    # A bounded summary survives even when one failed snapshot exceeds the cap.
    $logFile=''
    if($category -eq 'abnormal'){
     $log=@(foreach($path in $group.Paths){Get-ChildItem -LiteralPath $path -File -Recurse -Filter 'UE4SS.log'}) | Select-Object -First 1
     if($log){$logFile=$log.FullName}
    }
    Save-AC8RetentionSummary $package $category $group.Paths $group.Bytes $group.Stage $logFile
   }
   foreach($target in $group.Paths){
    $target=[IO.Path]::GetFullPath($target)
    if((Split-Path $target -Parent) -notin $allowedParents){throw 'Retention target escaped backup folders.'}
    Assert-AC8NoLinks $target -Tree
    if($Preview){Write-Output $target}else{Remove-Item -LiteralPath $target -Recurse -Force;Write-Host ('Removed expired MOD backup: '+$target)}
   }
  }
 }
 Invoke-AC8LogRetention -PackageRoot $package -Groups $retained -MaxBytes $MaxLogBytes -Preview:$Preview
 }finally{
  # Remove-Item -Force can clear the attribute on surviving hard links, too.
  foreach($file in $readOnly){if(Test-Path -LiteralPath $file.FullName){$file.IsReadOnly=$true}}
 }
}

# Inactive snapshot data only; never link game files or package resources.
# Shared files are read-only. Lifecycle/ownership metadata stays independent.
function Optimize-AC8BackupFiles {
 param([Parameter(Mandatory=$true)][string]$PackageRoot)
 $groups=@(Get-AC8BackupGroups $PackageRoot | Where-Object {!$_.Protected -and $_.Category -in @('normal','abnormal')})
 $files=@(foreach($group in $groups){foreach($path in $group.Paths){Get-ChildItem -LiteralPath $path -File -Recurse -Force | Where-Object {$_.Name -notin @('monitor-status.json','session-status.json','cleanup-report.json','completed-session.json') -and $_.Name -notlike '*.dedup-*'}}})
 foreach($sameSize in $files | Group-Object Length | Where-Object {$_.Count -gt 1}){
  $known=@{}
  foreach($file in $sameSize.Group){
   $hash=(Get-AC8FileHash -LiteralPath $file.FullName).Hash
   if(!$known.ContainsKey($hash)){$known[$hash]=$file.FullName;continue}
   $temp=$file.FullName+'.dedup-'+[guid]::NewGuid().ToString('N')
   # Force-removing an existing link may clear its shared read-only attribute.
   # Restore it even if replacement fails; no source needs to be made writable.
   $reference=Get-Item -LiteralPath $known[$hash]
   New-Item -ItemType HardLink -Path $temp -Target $reference.FullName -ErrorAction Stop | Out-Null
   try {
    Assert-AC8NoLinks $file.FullName
    Remove-Item -LiteralPath $file.FullName -Force
    Move-Item -LiteralPath $temp -Destination $file.FullName
   }finally{$reference.IsReadOnly=$true}
  }
 }
}

function Invoke-AC8BackupMaintenance([string]$PackageRoot,[string]$GameRoot,[switch]$Preview,[ValidateRange(0,60000)][int]$WaitMilliseconds=0) {
 $operation=Enter-AC8Operation $GameRoot -WaitMilliseconds $WaitMilliseconds
 try {
  Invoke-AC8BackupRetention -PackageRoot $PackageRoot -Preview:$Preview
  if(!$Preview){Optimize-AC8BackupFiles -PackageRoot $PackageRoot}
 }finally{Exit-AC8Operation $operation}
}
