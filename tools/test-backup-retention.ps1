param([Parameter(Mandatory=$true)][string]$WorkRoot,[string]$Repo)
if(!$Repo){$Repo=Split-Path $PSScriptRoot -Parent}
$ErrorActionPreference='Stop'
. (Join-Path $Repo 'Backup-Retention.ps1')
$testRoot=Join-Path $WorkRoot ('tests-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $testRoot | Out-Null
function Fixture($Name){$p=Join-Path $testRoot $Name;New-Item -ItemType Directory -Path $p | Out-Null;return $p}
function Session($Root,[int]$N,$Status='complete',[int]$Size=1024,[switch]$NoArchive){
 $s=Join-Path $Root ('sessions/20261104-1200'+$N.ToString('00')+'-'+$N.ToString('x8'))
 New-Item -ItemType Directory -Path $s -Force | Out-Null
 [IO.File]::WriteAllBytes((Join-Path $s 'snapshot.dat'),(New-Object byte[] $Size))
 if($Status -ne 'unfinished'){Write-AC8Json @{Status=$Status} (Join-Path $s 'session-status.json')}
 if(!$NoArchive){
  $a=Join-Path $Root ('cleanup-backups/20261104-1200'+$N.ToString('00')+'-'+$N.ToString('x32'))
  New-Item -ItemType Directory -Path $a -Force | Out-Null
  Write-AC8Json @{Status='complete'} (Join-Path $a 'cleanup-report.json')
  Write-AC8Json @{Results=$s;Id=$N.ToString('x32')} (Join-Path $a 'completed-session.json')
 }
 return $s
}
function Check($Condition,$Message){if(!$Condition){throw $Message}}

$f=Fixture 'counts'
foreach($i in 1..7){$null=Session $f $i}
foreach($i in 8..14){$null=Session $f $i $(if($i%2){'unfinished'}else{'failed'})}
$active=Session $f 0 'unfinished'
Write-AC8Json @{Results=$active;Id='active'} (Join-Path $f 'active-session.json')
$preview=@(Invoke-AC8BackupRetention $f -Preview)
Check ($preview.Count -eq 16) 'Expected four expired normal and four abnormal pairs'
Check ($preview -notcontains $active) 'Active session selected'
Invoke-AC8BackupRetention $f
$groups=@(Get-AC8BackupGroups $f)
Check (@($groups|Where-Object {$_.Category -eq 'normal'}).Count -eq 3) 'Normal count exceeded'
Check (@($groups|Where-Object {$_.Category -eq 'abnormal' -and !$_.Protected}).Count -eq 3) 'Abnormal count exceeded'
Check (Test-Path $active) 'Active session removed'
Check (@(Invoke-AC8BackupRetention $f -Preview).Count -eq 0) 'Retention not idempotent'
Write-Host 'PASS count caps, active exclusion, failed/unfinished retirement, preview, idempotence'

$f=Fixture 'bytes'
foreach($i in 1..3){$null=Session $f $i complete 4096}
foreach($i in 4..6){$s=Session $f $i failed 4096;Set-Content -LiteralPath (Join-Path $s 'UE4SS.log') -Value 'last-known-diagnostic'}
Invoke-AC8BackupRetention $f -MaxBytes 6000 -MaxAbnormalBytes 6000
foreach($c in @('normal','abnormal')){
 $g=@(Get-AC8BackupGroups $f|Where-Object {$_.Category -eq $c})
 Check ($g.Count -eq 1 -and ($g|Measure-Object Bytes -Sum).Sum -le 6000) ('Capacity exceeded: '+$c)
}
Invoke-AC8BackupRetention $f -MaxBytes 1 -MaxAbnormalBytes 1
Check (@(Get-AC8BackupGroups $f).Count -eq 0) 'Single oversized group escaped cap'
$history=@(Read-AC8BackupRecord (Join-Path $f 'backup-retention-history.json'))
Check (@($history|Where-Object {$_.LogTail -match 'last-known-diagnostic'}).Count -gt 0) 'Failed diagnostic summary lost'
Check ($history.Count -le 20) 'Summary history unbounded'
Write-Host 'PASS byte caps, oversized snapshots and bounded diagnostic summary'

$f=Fixture 'orphans'
$null=Session $f 1 unfinished 1024 -NoArchive
$s=Session $f 2 unfinished 1024 -NoArchive
Set-Content -LiteralPath (Join-Path $s 'session-status.json') -Value '{'
foreach($i in 3..7){
 $a=Join-Path $f ('cleanup-backups/completed-'+$i.ToString('x32'))
 New-Item -ItemType Directory -Path $a -Force | Out-Null
 Set-Content -LiteralPath (Join-Path $a 'cleanup-report.json') -Value '{'
}
$unknown=Join-Path $f 'sessions/my-other-mod';New-Item -ItemType Directory -Path $unknown | Out-Null
Invoke-AC8BackupRetention $f
Check (@(Get-AC8BackupGroups $f).Count -eq 3) 'Orphan or corrupted metadata bypassed count'
Check (Test-Path $unknown) 'Unknown folder deleted'
Set-Content -LiteralPath (Join-Path $f 'active-session.json') -Value '{'
$blocked=$false;try{Invoke-AC8BackupRetention $f}catch{$blocked=$true}
Check $blocked 'Damaged active state did not stop maintenance'
Write-Host 'PASS orphan archives, missing/corrupt metadata, unknown folder and damaged active state'

$f=Fixture 'live-monitor'
$s=Session $f 1 unfinished 2048 -NoArchive
Write-AC8Json @{MonitorPID=$PID;Time=[DateTime]::UtcNow.ToString('o');Stage='monitoring'} (Join-Path $s 'monitor-status.json')
Invoke-AC8BackupRetention $f -MaxAbnormalBytes 1
Check (Test-Path $s) 'Live monitor without active record not protected'
$a=Join-Path $f ('cleanup-backups/20261104-120001-'+('a'*32));New-Item -ItemType Directory -Path $a -Force | Out-Null
Write-AC8Json @{Results=$s;Id='active'} (Join-Path $f 'active-session.json')
Invoke-AC8BackupRetention $f -MaxAbnormalBytes 1
Check (Test-Path $a) 'Unfinished cleanup of active record not protected'
Write-Host 'PASS live monitor and pending recovery archive protection'

$f=Fixture 'dedup'
$s1=Session $f 1 complete 2048
$s2=Session $f 2 failed 2048
$source=Join-Path $f 'original.sav';Copy-Item -LiteralPath (Join-Path $s1 'snapshot.dat') -Destination $source
$before=(Get-FileHash -LiteralPath $source).Hash
Optimize-AC8BackupFiles $f
$links=(& fsutil hardlink list (Join-Path $s1 'snapshot.dat')) -join "`n"
Check ($links -match '120002') 'All-extension failed snapshot dedup did not share content'
Check ((Get-Item -LiteralPath (Join-Path $s1 'snapshot.dat')).IsReadOnly) 'Shared data not read-only'
Check (!(Get-Item -LiteralPath (Join-Path $s2 'session-status.json')).IsReadOnly) 'Lifecycle metadata linked'
$blocked=$false;try{[IO.File]::WriteAllText((Join-Path $s2 'snapshot.dat'),'edit')}catch{$blocked=$true}
Check $blocked 'Normal file editing changed shared data'
Optimize-AC8BackupFiles $f
Invoke-AC8BackupRetention $f -MaxAbnormalBytes 1
Check ((Get-FileHash -LiteralPath (Join-Path $s1 'snapshot.dat')).Hash -eq $before) 'Deleting one link damaged retained content'
Check ((Get-Item -LiteralPath (Join-Path $s1 'snapshot.dat')).IsReadOnly) 'Deletion cleared surviving link read-only protection'
Check ((Get-FileHash -LiteralPath $source).Hash -eq $before -and !((Get-Item $source).IsReadOnly)) 'Original source changed or linked'
Write-Host 'PASS read-only all-extension dedup, metadata independence, repeat runs and original separation'

$f=Fixture 'auxiliary'
foreach($spec in @(@('settings-backups','20261104-120000-001-'),@('resource-backups','20261104-120000-'),@('update-backups','fpmci-fix-1.1.2-20261104-120000-001-'))){
 foreach($i in 1..6){$name=$spec[1]+$(if($spec[0] -eq 'resource-backups'){$i.ToString('x8')}else{$i.ToString('x6')});$d=Join-Path $f ($spec[0]+'/'+$name);New-Item -ItemType Directory -Path $d -Force | Out-Null;Set-Content (Join-Path $d 'data') 'backup'}
}
$logs=Join-Path $f 'diagnostics';New-Item -ItemType Directory -Path $logs | Out-Null
foreach($i in 1..25){$prefix=Join-Path $logs ('session-monitor-20261104-120000-'+$i.ToString('x8'));Set-Content ($prefix+'.log') 'output';Set-Content ($prefix+'.error.log') 'error'}
$env:AC8_MONITOR_LOG_PREFIX=Join-Path $logs 'session-monitor-20261104-120000-00000001'
Invoke-AC8BackupRetention $f
$groups=@(Get-AC8BackupGroups $f)
foreach($c in @('settings','updates','resources')){Check (@($groups|Where-Object {$_.Category -eq $c}).Count -eq 3) ('Auxiliary count exceeded: '+$c)}
Check (@($groups|Where-Object {$_.Category -eq 'diagnostics' -and !$_.Protected}).Count -eq 20) 'Logs count exceeded'
Check (Test-Path ($env:AC8_MONITOR_LOG_PREFIX+'.log')) 'Current monitor log deleted'
$env:AC8_MONITOR_LOG_PREFIX=''
Check (@(Read-AC8BackupRecord (Join-Path $f 'backup-retention-history.json')).Count -le 20) 'Maintenance summary exceeded 20'
Write-Host 'PASS rollback limits, paired logs and current log protection'

$f=Fixture 'shared-log-budget'
New-Item -ItemType Directory -Path (Join-Path $f 'payload') | Out-Null
[IO.File]::WriteAllBytes((Join-Path $f 'payload/mod.bin'),(New-Object byte[] (4MB)))
foreach($i in 1..3){
 $s=Session $f $i complete 16
 [IO.File]::WriteAllBytes((Join-Path $s 'recording.csv'),(New-Object byte[] (2MB)))
 [IO.File]::WriteAllBytes((Join-Path $s 'UE4SS.log'),(New-Object byte[] (1MB)))
}
$active=Session $f 4 unfinished 16 -NoArchive
[IO.File]::WriteAllBytes((Join-Path $active 'active.csv'),(New-Object byte[] (6MB)))
Write-AC8Json @{Results=$active;Id='active'} (Join-Path $f 'active-session.json')
$preview=@(Invoke-AC8BackupRetention $f -Preview)
Check (@($preview|Where-Object {$_ -match '\.(log|csv)$'}).Count -gt 0) 'Shared log budget not included in preview'
Check ((Get-Item (Join-Path $active 'active.csv')).Length -eq 6MB) 'Preview changed active log'
Invoke-AC8BackupRetention $f
$g=@(Get-AC8BackupGroups $f|Where-Object {!$_.Protected})
[long]$logBytes=(Get-ChildItem -LiteralPath (Join-Path $f 'sessions') -File -Recurse | Where-Object {$_.FullName -notlike ($active+'\*') -and $_.Extension -in @('.log','.csv')} | Measure-Object Length -Sum).Sum
$logBytes+=(Get-Item (Join-Path $f 'backup-retention-history.json')).Length
Check ($logBytes -le 4MB) 'Retained logs and summaries exceeded MOD payload size'
Check (@($g|Where-Object {$_.Category -eq 'normal'}).Count -eq 3) 'Log pruning removed session records'
Check ((Get-Item (Join-Path $active 'active.csv')).Length -eq 6MB) 'Active recording was truncated'
Check (@(Invoke-AC8BackupRetention $f -Preview).Count -eq 0) 'Shared log cleanup not idempotent'
Write-Host 'PASS shared log budget across snapshots, MOD-size ceiling, preserved session data and active exclusion'

$f=Fixture 'junction'
$outside=Fixture 'outside';Set-Content (Join-Path $outside 'untouched.txt') 'external'
$sessions=Join-Path $f 'sessions';New-Item -ItemType Directory -Path $sessions | Out-Null
New-Item -ItemType Junction -Path (Join-Path $sessions '20261104-120001-00000001') -Target $outside | Out-Null
$blocked=$false;try{Invoke-AC8BackupRetention $f -MaxAbnormalBytes 1}catch{$blocked=$true}
Check ($blocked -and (Test-Path (Join-Path $outside 'untouched.txt'))) 'Junction escaped protected roots'
Write-Host 'PASS junction rejected before any external access/deletion'

foreach($name in @('Backup-Retention.ps1','Launch-Offline.ps1','Gui-Core.ps1','Run-Console.ps1','Recover-Cleanup.ps1','Check-Package.ps1')){
 $errors=$null;[void][Management.Automation.Language.Parser]::ParseFile((Join-Path $Repo $name),[ref]$null,[ref]$errors)
 Check (!$errors.Count) ('Syntax failed: '+$name+($errors|Out-String))
}
Write-Host ('PASS Windows PowerShell '+$PSVersionTable.PSVersion+' syntax; fixtures: '+$testRoot)
