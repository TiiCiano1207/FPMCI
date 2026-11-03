function Invoke-AC8BackupRetention {
 param([Parameter(Mandatory=$true)][string]$PackageRoot,[int]$Keep=3,[switch]$Preview)
 if($Keep -lt 1){throw 'Keep must be positive.'}
 $package=[IO.Path]::GetFullPath($PackageRoot).TrimEnd('\','/')
 $sessions=Join-Path $package 'sessions'
 $backups=Join-Path $package 'cleanup-backups'
 $activePath=Join-Path $package 'active-session.json'
 $activeResults=if(Test-Path -LiteralPath $activePath){[IO.Path]::GetFullPath([string](Get-Content -LiteralPath $activePath -Raw | ConvertFrom-Json).Results)}else{''}
 $completed=@()
 if(!(Test-Path -LiteralPath $backups)){return}
 Assert-AC8NoLinks $backups
 Assert-AC8NoLinks $sessions
 foreach($archive in Get-ChildItem -LiteralPath $backups -Directory){
  if($archive.Name -notmatch '^\d{8}-\d{6}-[a-f0-9]{32}$'){continue}
  Assert-AC8NoLinks $archive.FullName -Tree
  $record=Join-Path $archive.FullName 'completed-session.json'
  $report=Join-Path $archive.FullName 'cleanup-report.json'
  if(!(Test-Path -LiteralPath $record) -or !(Test-Path -LiteralPath $report)){continue}
  $state=Get-Content -LiteralPath $record -Raw | ConvertFrom-Json
  $cleanup=Get-Content -LiteralPath $report -Raw | ConvertFrom-Json
  if($cleanup.Status -ne 'complete'){continue}
  $session=[IO.Path]::GetFullPath([string]$state.Results)
  if((Split-Path $session -Parent) -ine $sessions -or (Split-Path $session -Leaf) -notmatch '^\d{8}-\d{6}-[a-f0-9]{8}$' -or $session -ieq $activeResults){continue}
  if(!(Test-Path -LiteralPath $session -PathType Container)){continue}
  Assert-AC8NoLinks $session -Tree
  $status=Join-Path $session 'session-status.json'
  if(Test-Path -LiteralPath $status){
   if((Get-Content -LiteralPath $status -Raw | ConvertFrom-Json).Status -ne 'complete'){continue}
  }elseif(!(Test-Path -LiteralPath (Join-Path $session 'save-hashes-after.json'))){continue}
  $completed += [pscustomobject]@{Archive=$archive.FullName;Session=$session;Order=(Split-Path $session -Leaf)}
 }
 foreach($item in $completed | Sort-Object Order -Descending | Select-Object -Skip $Keep){
  foreach($target in @($item.Session,$item.Archive)){
   # Both resolved parents are checked again at the mutation boundary.
   if((Split-Path $target -Parent) -notin @($sessions,$backups)){throw 'Retention target escaped backup folders.'}
   Assert-AC8NoLinks $target -Tree
   if($Preview){Write-Output $target}else{Remove-Item -LiteralPath $target -Recurse -Force;Write-Host ('已移除旧的已完成备份：'+$target)}
  }
 }
}

# Only immutable, completed backup data is coalesced. No game/source files are linked.
function Optimize-AC8BackupFiles {
 param([string]$PackageRoot)
 $package=[IO.Path]::GetFullPath($PackageRoot).TrimEnd('\','/')
 $known=@{}
 foreach($folder in @('cleanup-backups','sessions')){
  $base=Join-Path $package $folder
  if(!(Test-Path -LiteralPath $base)){continue}
  Assert-AC8NoLinks $base
  foreach($dir in Get-ChildItem -LiteralPath $base -Directory){
   if($folder -eq 'cleanup-backups'){
    $report=Join-Path $dir.FullName 'cleanup-report.json'
    if(!(Test-Path -LiteralPath $report) -or (Get-Content -LiteralPath $report -Raw | ConvertFrom-Json).Status -ne 'complete'){continue}
   }else{
    if(!(Test-Path -LiteralPath (Join-Path $dir.FullName 'save-hashes-after.json'))){continue}
   }
   Assert-AC8NoLinks $dir.FullName -Tree
   foreach($file in Get-ChildItem -LiteralPath $dir.FullName -File -Recurse | Where-Object {$_.Extension -in @('.sav','.dll','.png','.ttf','.pyd')}){
    $hash=(Get-AC8FileHash -LiteralPath $file.FullName).Hash
    if(!$known.ContainsKey($hash)){$known[$hash]=$file.FullName;continue}
    $temp=$file.FullName+'.dedup-'+[guid]::NewGuid().ToString('N')
    New-Item -ItemType HardLink -Path $temp -Target $known[$hash] -ErrorAction Stop | Out-Null
    # The replacement target was enumerated under, and validated against, these roots.
    if(!$file.FullName.StartsWith($base+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'Backup path escaped its root.'}
    Remove-Item -LiteralPath $file.FullName -Force
    Move-Item -LiteralPath $temp -Destination $file.FullName
   }
  }
 }
}
