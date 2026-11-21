param([Parameter(Mandatory=$true)][string]$WorkRoot,[string]$Repo)
$ErrorActionPreference='Stop'
if(!$Repo){$Repo=Split-Path $PSScriptRoot -Parent}
. (Join-Path $Repo 'ExtraMods-Settings.ps1')
. (Join-Path $Repo 'MouseAim-Settings.ps1')
function Check($Value,[string]$Message){if(!$Value){throw $Message}}
# All deployment, recovery and backup paths below belong to this fixture.
function Get-Process {param($Name) if($Name -ne 'AceCombat8'){throw 'Unexpected process check'}}
$fixture=Join-Path ([IO.Path]::GetFullPath($WorkRoot)) ('extra-'+[guid]::NewGuid().ToString('N'))
$root=Join-Path $fixture 'package'
$source=Join-Path $fixture 'import'
$game=Join-Path $fixture 'game'
$w64=Join-Path $game 'Game/Binaries/Win64'
$backup=Join-Path $fixture 'backups'
foreach($folder in @($root,$w64,(Join-Path $source 'Example/Scripts'),(Join-Path $source 'Example/payloads'),(Join-Path $fixture 'Small/Scripts'))){
 [void][IO.Directory]::CreateDirectory($folder)
}
Set-Content -LiteralPath (Join-Path $w64 'AceCombat8.exe') -Value 'fixture'
Set-Content -LiteralPath (Join-Path $source 'Example/Scripts/main.lua') -Value 'return true'
Set-Content -LiteralPath (Join-Path $fixture 'Small/Scripts/main.lua') -Value 'return true'
Set-Content -LiteralPath (Join-Path $source 'Example/UE4SS.dll') -Value 'external loader'
foreach($ext in @('pak','utoc','ucas')){
 Set-Content -LiteralPath (Join-Path $source "Example/payloads/aircraft.$ext") -Value 'asset'
}
Set-Content -LiteralPath (Join-Path $source 'outside.pak') -Value 'outside'
Add-Type -AssemblyName System.IO.Compression,System.IO.Compression.FileSystem
$zip=Join-Path $fixture 'aircraft.zip'
[IO.Compression.ZipFile]::CreateFromDirectory($source,$zip)
function Import-Fixture([string]$Path){
 $p=Invoke-AC8ExtraModAction @{Action='ExtraPreview';ExtraPath=$Path} $root
 Check $p.Success $p.Message
 Invoke-AC8ExtraModAction @{Action='ExtraImport';ExtraPath=$Path;ExtraToken=$p.ExtraToken} $root
}
$null=Import-Fixture $zip
$null=Import-Fixture (Join-Path $fixture 'Small')
$installed=Join-Path $root 'ue4ss-mods/Example'
Check (!(Test-Path (Join-Path $installed 'UE4SS.dll'))) 'An external loader was imported'
Check (!(Test-Path (Join-Path $installed 'outside.pak'))) 'An outer Pak was imported'
Check (@(Get-ChildItem (Join-Path $installed 'payloads') -File).Count -eq 3) 'Pak/IoStore resources missing'
Check (!(Invoke-AC8ExtraModAction @{Action='ExtraPreview';ExtraPath=$zip} $root).Success) 'Existing MOD could be overwritten'
$badZip=Join-Path $fixture 'bad.zip'
$archive=[IO.Compression.ZipFile]::Open($badZip,[IO.Compression.ZipArchiveMode]::Create)
try{$null=$archive.CreateEntry('../escape.lua')}finally{$archive.Dispose()}
$refused=$false
try{$null=Invoke-AC8ExtraModAction @{Action='ExtraPreview';ExtraPath=$badZip} $root}catch{$refused=$true}
Check $refused 'Unsafe archive path accepted'
$null=Invoke-AC8ExtraModAction @{Action='ExtraDisable';ExtraName='Small'} $root
Check (@(Get-AC8EnabledExtraMods $root).Count -eq 1) 'Disabled MOD selected for deployment'
$null=Invoke-AC8ExtraModAction @{Action='ExtraEnable';ExtraName='_Small'} $root

foreach($round in 1..2){
 $mods=@(Get-AC8EnabledExtraMods $root)
 $runtime=Join-Path $w64 'ue4ss'
 $modPath=Join-Path $runtime 'Mods'
 [void][IO.Directory]::CreateDirectory($modPath)
 $id=[guid]::NewGuid().ToString()
 Set-Content -LiteralPath (Join-Path $runtime 'AC8SourceInit-owner.txt') -Value $id
 Set-Content -LiteralPath (Join-Path $modPath 'mods.txt') -Value 'AC8MouseAim : 1'
 $state=[pscustomobject]@{Id=$id;Win64=$w64;ExtraMods=@($mods | Select-Object Name,Files)}
 Install-AC8ExtraMods $mods $modPath
 Check ((Get-Content (Join-Path $modPath 'mods.txt')) -contains 'Example : 1') 'MOD missing from load order'
 if($round -eq 2){
  Set-Content -LiteralPath (Join-Path $modPath 'Example/payloads/aircraft.pak') -Value 'other'
  Set-Content -LiteralPath (Join-Path $modPath 'Example/new.txt') -Value 'generated'
  $unknown=Join-Path $modPath 'Unknown'
  [void][IO.Directory]::CreateDirectory($unknown)
  $refused=$false
  try{$null=Invoke-AC8Cleanup -GameRoot $game -BackupRoot $backup -State $state}catch{$refused=$_.Exception.Message -match 'Other UE4SS'}
  Check ($refused -and (Test-Path $unknown)) 'Unknown MOD not protected'
  # Fixture directory is empty and was created immediately above.
  [IO.Directory]::Delete($unknown)
 }
 $saved=Invoke-AC8Cleanup -GameRoot $game -BackupRoot $backup -State $state
 Check (!(Test-Path $runtime)) 'Runtime cleanup incomplete'
 Check (!(Test-Path (Join-Path $saved 'ue4ss/Mods/Example/payloads/aircraft.ucas'))) 'Unchanged resource duplicated in backup'
 Check (!(Test-Path (Join-Path $saved 'ue4ss/Mods/Small'))) 'Unchanged MOD duplicated in backup'
 if($round -eq 2){
  Check ((Get-Content (Join-Path $saved 'ue4ss/Mods/Example/payloads/aircraft.pak')) -eq 'other') 'Changed asset missing from backup'
  Check (Test-Path (Join-Path $saved 'ue4ss/Mods/Example/new.txt')) 'Generated file missing from backup'
 }
 Check ((Get-Content (Join-Path $installed 'payloads/aircraft.pak')) -eq 'asset') 'Managed original changed'
}
$null=Invoke-AC8ExtraModAction @{Action='ExtraRemove';ExtraName='Small'} $root
Check (@(Get-AC8EnabledExtraMods $root).Count -eq 1) 'Removed MOD still enabled'
Check (@(Get-ChildItem (Join-Path $root 'ue4ss-mods-removed') -Filter main.lua -Recurse).Count -eq 1) 'Removed original not recoverable'
$ini=Join-Path $fixture 'mouse.ini'
Set-Content -LiteralPath $ini -Value 'sensitivity=0.25'
Check ((Read-MouseSettings $ini).flight_recording -eq 0) 'Legacy configuration enables flight recording'
Add-Content -LiteralPath $ini -Value 'flight_recording=1'
Check ((Read-MouseSettings $ini).flight_recording -eq 1) 'Recording opt-in not read'
'PASS extra MOD import, exclusions, enable/disable, repeated deployment, recovery, backup filtering and recording default.'
