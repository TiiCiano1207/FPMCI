param([Parameter(Mandatory=$true)][string]$WorkRoot,[string]$Repo)
if(!$Repo){$Repo=Split-Path $PSScriptRoot -Parent}
$ErrorActionPreference='Stop'
$testRoot=Join-Path $WorkRoot ('lifecycle-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $testRoot | Out-Null
function Check($Condition,$Message){if(!$Condition){throw $Message}}
. (Join-Path $Repo 'Backup-Retention.ps1')

# Execute the actual cleanup and outer-finally code with game/filesystem work
# replaced by isolated stubs. Optional analysis throws after recovery succeeds.
$f=Join-Path $testRoot 'cleanup';New-Item -ItemType Directory -Path $f | Out-Null
Copy-Item (Join-Path $Repo 'Launch-Offline.ps1') $f
Set-Content (Join-Path $f 'Install-Common.ps1') @'
function Resolve-AC8PackageGameRoot {$PSScriptRoot}
function Assert-AC8PackageLocation {}
function Invoke-AC8OptionalAnalysis {throw 'simulated diagnostics failure'}
'@
Set-Content (Join-Path $f 'Cleanup-Core.ps1') @'
function Enter-AC8Operation {return 'test-lock'}
function Exit-AC8Operation {Set-Content (Join-Path $PSScriptRoot 'lock-released') 'yes'}
function Assert-AC8NoLinks {}
function Write-AC8Json($Value,$Path){ConvertTo-Json -InputObject $Value | Set-Content -LiteralPath $Path}
function Invoke-AC8Cleanup {
 $archive=Join-Path $PSScriptRoot 'cleanup-backups/20261104-120000-11111111111111111111111111111111'
 New-Item -ItemType Directory -Path $archive -Force | Out-Null
 return $archive
}
'@
Set-Content (Join-Path $f 'Backup-Retention.ps1') @'
function Invoke-AC8BackupRetention {param($PackageRoot,[switch]$Preview) Add-Content (Join-Path $PSScriptRoot 'maintenance-ran') 'retention'}
function Optimize-AC8BackupFiles {param($PackageRoot) Add-Content (Join-Path $PSScriptRoot 'maintenance-ran') 'dedup'}
'@
Set-Content (Join-Path $f 'MouseAim-Settings.ps1') ''
Set-Content (Join-Path $f 'Runtime-Settings.ps1') ''
$session=Join-Path $f 'sessions/20261104-120000-11111111'
New-Item -ItemType Directory -Path $session -Force | Out-Null
Write-AC8Json @{Results=$session;Id='fixture'} (Join-Path $f 'active-session.json')
# Trigger a diagnostics failure in the real helper without launching any game.
# CleanupOnly supplies Analyze:false, so inject its helper body to use Analyze:true
# only inside this isolated fixture to test the optional-analysis failure route.
$script=Get-Content (Join-Path $f 'Launch-Offline.ps1') -Raw -Encoding UTF8
$script=$script.Replace('-Analyze:$false','-Analyze:$true')
Set-Content (Join-Path $f 'Launch-Offline.ps1') $script -Encoding UTF8
$originalLocalAppData=$env:LOCALAPPDATA
try {
 $env:LOCALAPPDATA=Join-Path $f 'appdata'
 & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $f 'Launch-Offline.ps1') -CleanupOnly *> (Join-Path $f 'output.log')
}finally{$env:LOCALAPPDATA=$originalLocalAppData}
Check ($LASTEXITCODE -eq 0) 'Fixture cleanup failed'
Check (!(Test-Path (Join-Path $f 'active-session.json'))) 'Active record not retired'
Check ((Get-Content (Join-Path $session 'session-status.json') -Raw | ConvertFrom-Json).Status -eq 'complete') 'Recovery status missing before analysis'
Check ((Get-Content (Join-Path $f 'output.log') -Raw) -match 'simulated diagnostics failure') 'Diagnostics failure not exercised'
Check ((Get-Content (Join-Path $f 'maintenance-ran') -Raw) -match 'retention[\s\S]*dedup') 'Final maintenance skipped after optional diagnostics failure'
Check (Test-Path (Join-Path $f 'lock-released')) 'Operation lock leaked'
Write-Host 'PASS real cleanup helper retires state, writes status and maintains backups after optional diagnostics failure'

# GUI behavior uses the actual function AST, stubbing only service boundaries.
$guiFixture=Join-Path $testRoot 'gui';New-Item -ItemType Directory -Path $guiFixture | Out-Null
$old=@'
$ErrorActionPreference='Stop'
$fixture=Join-Path $PSScriptRoot 'fixture'
New-Item -ItemType Directory -Path $fixture -Force | Out-Null
$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot 'Gui-Core.ps1'),[ref]$null,[ref]$null)
$node=$ast.Find({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Invoke-AC8GuiAction'},$true)
Invoke-Expression $node.Extent.Text
function Resolve-AC8GameRoot($p){$p}
function Assert-AC8PackageLocation {}
function Assert-AC8NoLinks {}
function Get-AC8FileHash {@{Hash='3E47FD42858D1F2B81E59D7F57394A014C0EB6AAF4C02EE3DA351B6A42936BE2'}}
function Get-AC8Residuals {if($global:residual){'ue4ss'}}
function Get-Process {param($Name) if($global:running -and $Name -eq 'AceCombat8'){@{Id=42}}}
function Stop-AC8Problem($code,$message,$hint){throw $code}
function Get-AC8GuiSavedPath($root,$name){if($name -eq 'game-path.txt'){'fixture-game'}else{Join-Path $fixture 'steam.exe'}}
function Read-FeatureSettings {@{MissileMode='guidance'}}
Set-Content (Join-Path $fixture 'steam.exe') ''
Set-Content (Join-Path $fixture 'Check-Package.ps1') ''
Set-Content (Join-Path $fixture 'Launch-AC8-via-Steam.ps1') '$global:started=$true'
Set-Content (Join-Path $fixture 'Launch-Offline.ps1') ('param([switch]$CleanupOnly,[string]$GameRoot)'+[Environment]::NewLine+'$global:recovered++;if($global:failRecovery){throw "OWNERSHIP_MISMATCH"};Remove-Item -LiteralPath (Join-Path $PSScriptRoot "active-session.json");$global:residual=$false')
foreach($case in @('recorded','unknown','failed-recovery','running','clean','save')){
 $global:running=$case -eq 'running';$global:failRecovery=$case -eq 'failed-recovery'
 $global:residual=$case -ne 'clean';$global:started=$false;$global:recovered=0
 $state=Join-Path $fixture 'active-session.json'
 if(Test-Path $state){Remove-Item -LiteralPath $state}
 if($case -in @('recorded','failed-recovery','running','save')){Set-Content $state '{}'}
 $errorCode=''
 try{$result=Invoke-AC8GuiAction -Action $(if($case -eq 'save'){'Save'}else{'Start'}) -Root $fixture -GamePath fixture-game -SteamPath (Join-Path $fixture 'steam.exe') -MissileMode guidance}catch{$errorCode=$_.Exception.Message}
 switch($case){
  'recorded'{if(!$global:started -or $global:recovered -ne 1){throw "Recorded session not resumed: $errorCode"}}
  'clean'{if(!$global:started -or $global:recovered){throw "Clean launch changed: $errorCode"}}
  'unknown'{if($errorCode -ne 'LOADER_CONFLICT' -or $global:recovered -or $global:started){throw 'Unknown files not blocked'}}
  'failed-recovery'{if($errorCode -ne 'OWNERSHIP_MISMATCH' -or $global:started -or !(Test-Path $state)){throw 'Recovery failure not preserved'}}
  'running'{if($errorCode -ne 'GAME_RUNNING' -or $global:recovered){throw 'Running game not protected'}}
  'save'{if($errorCode -ne 'LOADER_CONFLICT' -or $global:recovered){throw 'Save unexpectedly restored files'}}
 }
 Write-Host "PASS $case"
}

'@
$old=$old.Replace("`$fixture=Join-Path `$PSScriptRoot 'fixture'", "`$fixture='"+$guiFixture+"'")
$old=$old.Replace("(Join-Path `$PSScriptRoot 'Gui-Core.ps1')", "'"+(Join-Path $Repo 'Gui-Core.ps1')+"'")
$old=$old.Replace('function Resolve-AC8GameRoot', 'function Invoke-AC8BackupMaintenance {$global:maintenance++}'+[Environment]::NewLine+'function Resolve-AC8GameRoot')
$old=$old.Replace("'recorded'{if(!`$global:started", "'recorded'{if(!`$global:maintenance){throw 'GUI startup skipped maintenance'};if(!`$global:started")
Set-Content (Join-Path $testRoot 'gui-test.ps1') $old -Encoding UTF8
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $testRoot 'gui-test.ps1')
Check ($LASTEXITCODE -eq 0) 'GUI regression test failed'

# The visible console forwards both streams; its independent worker survives it.
$f=Join-Path $testRoot 'monitor';New-Item -ItemType Directory -Path $f | Out-Null
Copy-Item (Join-Path $Repo 'Run-Console.ps1') $f
Set-Content (Join-Path $f 'Install-Common.ps1') ''
Set-Content (Join-Path $f 'Start-ModSession.ps1') @'
Set-Content (Join-Path $PSScriptRoot 'started.txt') $PID
Write-Host 'worker-output-visible'
Write-Error 'worker-error-visible' -ErrorAction Continue
Start-Sleep -Seconds 4
Set-Content (Join-Path $PSScriptRoot 'finished.txt') 'finished'
Write-Host 'worker-finished-visible'
'@
$args='-NoProfile -ExecutionPolicy Bypass -File "'+(Join-Path $f 'Run-Console.ps1')+'" -Action Session'
$front=Start-Process (Join-Path $PSHOME 'powershell.exe') -ArgumentList $args -WindowStyle Hidden -RedirectStandardOutput (Join-Path $f 'front.log') -RedirectStandardError (Join-Path $f 'front.error.log') -PassThru
$deadline=[DateTime]::UtcNow.AddSeconds(15)
while(!(Test-Path (Join-Path $f 'started.txt')) -and [DateTime]::UtcNow -lt $deadline){Start-Sleep -Milliseconds 100}
Check (Test-Path (Join-Path $f 'started.txt')) 'Monitor failed to start'
Start-Sleep -Milliseconds 900
Check ((Get-Content (Join-Path $f 'front.log') -Raw) -match 'worker-output-visible') 'Front window did not stream stdout live'
Check ((Get-Content (Join-Path $f 'front.log') -Raw) -match 'worker-error-visible') 'Front window did not stream stderr live'
Stop-Process -Id $front.Id
$deadline=[DateTime]::UtcNow.AddSeconds(10)
while(!(Test-Path (Join-Path $f 'finished.txt')) -and [DateTime]::UtcNow -lt $deadline){Start-Sleep -Milliseconds 100}
Check (Test-Path (Join-Path $f 'finished.txt')) 'Worker died with console'
Write-Host 'PASS live stdout/stderr forwarding and detached monitor survives frontend termination'

# A second process owns the same mutex. Maintenance must refuse to touch data.
$f=Join-Path $testRoot 'lock';New-Item -ItemType Directory -Path $f | Out-Null
$lockWorker=Join-Path $f 'hold.ps1'
Set-Content $lockWorker (". '"+(Join-Path $Repo 'PowerShell-Compat.ps1')+"'`n`$m=Enter-AC8Operation '"+$f+"'`ntry{Set-Content '"+(Join-Path $f 'ready')+"' 'ready';Start-Sleep -Seconds 5}finally{Exit-AC8Operation `$m}")
$p=Start-Process (Join-Path $PSHOME 'powershell.exe') -ArgumentList ('-NoProfile -ExecutionPolicy Bypass -File "'+$lockWorker+'"') -WindowStyle Hidden -PassThru
$deadline=[DateTime]::UtcNow.AddSeconds(10)
while(!(Test-Path (Join-Path $f 'ready')) -and [DateTime]::UtcNow -lt $deadline){Start-Sleep -Milliseconds 100}
$blocked=$false;try{Invoke-AC8BackupMaintenance $f $f}catch{$blocked=$_.Exception.Data['AC8Code'] -eq 'SESSION_BUSY'}
Check $blocked 'Concurrent session lock did not block maintenance'
$p.WaitForExit()
Write-Host ('PASS cross-process operation lock; fixtures: '+$testRoot)
