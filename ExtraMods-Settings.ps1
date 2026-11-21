# Managing the player's extra UE4SS mods (2.5.0): add from a zip or a folder, enable/disable, remove to a backup.
# Works only in the player data folder: ue4ss-mods (what loads), ue4ss-mods-removed (backups of removed or replaced mods)
# and ue4ss-mods-staging (temporary). The game folder is never touched; deployment stays with Launch-Offline.ps1.
. (Join-Path $PSScriptRoot 'Cleanup-Core.ps1')

function Get-AC8ExtraModNameProblem([string]$Name) {
 if(!(Test-AC8ExtraModName $Name)){return '无效或保留的 MOD 名称'}
}
function Get-AC8IntegratedModPage([string]$Root,[string]$Name) {
 switch($Name.TrimStart('_')){
  'AC8EnhancedHUD' {return '常用设置'}
  'AcePilotsMod' {
   if(Test-Path -LiteralPath (Join-Path $Root "ue4ss-mods/$Name/acepilots_hook-26002268.dll") -PathType Leaf){
    return '敌方AI增强'
   }
  }
 }
}
function Get-AC8ExtraModDirectory([string]$DataRoot,[string]$Name) {
 if($Name -notin @('ue4ss-mods','ue4ss-mods-staging','ue4ss-mods-removed')){throw 'Invalid extra MOD directory.'}
 Assert-AC8NoLinks $DataRoot
 $path=Join-Path $DataRoot $Name
 if(!(Test-Path -LiteralPath $path)){[void][IO.Directory]::CreateDirectory($path)}
 Assert-AC8NoLinks $path
 return $path
}

function Test-AC8ModSkippedFile([string]$Name) {
 # Never installed with a mod: the UE4SS loader itself (this package brings its own). Pak/IoStore files inside a mod
 # folder belong to that mod (PW-MkI: AC8OverrideLoader\payloads mounts them itself) and are installed with it (2.5.2).
 return ($Name -in @('dwmapi.dll','UE4SS.dll','UE4SS-settings.ini','xinput1_3.dll','AVRT.dll'))
}
function Copy-AC8ModTree([string]$Source,[string]$Destination) {
 [void][IO.Directory]::CreateDirectory($Destination)
 foreach($child in (New-Object IO.DirectoryInfo($Source)).GetFileSystemInfos()){
  if($child.Attributes -band [IO.FileAttributes]::ReparsePoint){throw "Filesystem link in the mod: $($child.FullName)"}
  if($child -isnot [IO.DirectoryInfo] -and (Test-AC8ModSkippedFile $child.Name)){continue}
  $target=[IO.Path]::Combine($Destination,$child.Name)
  if($child -is [IO.DirectoryInfo]){Copy-AC8ModTree $child.FullName $target}else{[IO.File]::Copy($child.FullName,$target,$false)}
 }
}
function Expand-AC8ModArchive([string]$Zip,[string]$Destination) {
 # Zip only (System.IO.Compression). Entries must stay inside the destination; size and count are bounded.
 Add-Type -AssemblyName System.IO.Compression,System.IO.Compression.FileSystem
 $dest=[IO.Path]::GetFullPath($Destination).TrimEnd('\','/');[void][IO.Directory]::CreateDirectory($dest)
 $archive=[IO.Compression.ZipFile]::OpenRead($Zip)
 try{
  if($archive.Entries.Count -gt 50000){throw '压缩包里的文件太多（超过 50000 个）。'}
  $total=0L;foreach($entry in $archive.Entries){$total+=$entry.Length}
  if($total -gt 2GB){throw '压缩包解压后超过 2 GB，不像是 UE4SS Mod。'}
  foreach($entry in $archive.Entries){
   if((($entry.ExternalAttributes -shr 16) -band 0xF000) -eq 0xA000 -or ($entry.ExternalAttributes -band 0x400)){throw '压缩包含文件系统链接。'}
   $name=$entry.FullName.Replace('/','\')
   if(!$name -or $name.StartsWith('\') -or $name.Contains(':') -or $name -match '(^|\\)\.\.(\\|$)'){throw '压缩包含有不安全的路径，已拒绝。'}
   foreach($part in ($name.TrimEnd('\') -split '\\')){
    if(!$part -or $part -match '[<>"|?*\x00-\x1f]' -or $part -match '[. ]$' -or $part -match '^(CON|PRN|AUX|NUL|COM[0-9¹²³]|LPT[0-9¹²³])(?:\.|$)'){throw '压缩包含无效的 Windows 路径。'}
   }
   $target=[IO.Path]::GetFullPath([IO.Path]::Combine($dest,$name))
   if(!$target.StartsWith($dest+'\',[StringComparison]::OrdinalIgnoreCase)){throw '压缩包含有不安全的路径，已拒绝。'}
   if($name.EndsWith('\')){[void][IO.Directory]::CreateDirectory($target);continue}
   [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($target))
   [IO.Compression.ZipFileExtensions]::ExtractToFile($entry,$target,$false)
  }
 }finally{$archive.Dispose()}
}
function Get-AC8ModLayoutKind([string]$Path) {
 $kind=@()
 if(Test-Path -LiteralPath (Join-Path $Path 'Scripts\main.lua') -PathType Leaf){$kind+='Lua'}
 if(Test-Path -LiteralPath (Join-Path $Path 'dlls\main.dll') -PathType Leaf){$kind+='C++'}
 return ($kind -join '+')
}
function Find-AC8ModRoots([string]$Root,[int]$Depth=0) {
 # Folders with the standard UE4SS mod layout, outermost first; a found mod is not searched further.
 $kind=Get-AC8ModLayoutKind $Root
 if($kind){return @([pscustomobject]@{Path=[IO.Path]::GetFullPath($Root);Kind=$kind})}
 if($Depth -ge 6){return @()}
 $found=@()
 foreach($dir in @(Get-ChildItem -LiteralPath $Root -Directory -Force | Sort-Object Name)){
  if($dir.Attributes -band [IO.FileAttributes]::ReparsePoint){continue}
  $found+=@(Find-AC8ModRoots $dir.FullName ($Depth+1))
 }
 return $found
}
function Get-AC8ModNameFromSource([string]$Source) {
 # A mod packed without its own folder takes its name from the zip or folder name ("Some Mod v1.2.zip" -> SomeMod).
 $name=[IO.Path]::GetFileNameWithoutExtension($Source.TrimEnd('\','/'))
 $name=($name -replace '(?i)[ _.-]*v?\d+(\.\d+)+.*$','') -replace '[^A-Za-z0-9_.\-]',''
 return $name.TrimStart('_','.','-')
}
function New-AC8ExtraModPlan([string]$DataRoot,[string]$Source) {
 # Inspect a zip or folder without changing ue4ss-mods. A zip is unpacked into ue4ss-mods-staging; always finish
 # with Remove-AC8ExtraModPlan. Items: Name, Kind, Path, Problem, Existing (enabled/disabled/$null).
 $mods=Get-AC8ExtraModDirectory $DataRoot 'ue4ss-mods'
 $source=[IO.Path]::GetFullPath($Source).TrimEnd('\','/');$staging=$null
 if(Test-Path -LiteralPath $source -PathType Leaf){
  if([IO.Path]::GetExtension($source) -ine '.zip'){throw '只支持 .zip 压缩包或文件夹。7z／rar 请先解压，再选择解压出来的文件夹。'}
  $staging=Join-Path (Get-AC8ExtraModDirectory $DataRoot 'ue4ss-mods-staging') ([guid]::NewGuid().ToString('N'))
  Assert-AC8NoLinks $source
  try{Expand-AC8ModArchive $source $staging}catch{Remove-AC8ExtraModTree $staging;throw}
  $scan=$staging
 }elseif(Test-Path -LiteralPath $source -PathType Container){
  $inside=[IO.Path]::GetFullPath($DataRoot).TrimEnd('\')+'\'
  if(($source+'\').StartsWith($inside,[StringComparison]::OrdinalIgnoreCase) -or $inside.StartsWith($source+'\',[StringComparison]::OrdinalIgnoreCase)){throw '请选择数据文件夹以外的 Mod（例如下载并解压后的文件夹）。'}
  Assert-AC8NoLinks $source -Tree
  $scan=$source
 }else{throw "找不到：$Source"}
 try {
 $items=@();$warnings=@()
 foreach($root in @(Find-AC8ModRoots $scan)){
  $name=if($root.Path -eq [IO.Path]::GetFullPath($scan)){Get-AC8ModNameFromSource $source}else{Split-Path $root.Path -Leaf}
  $problem=Get-AC8ExtraModNameProblem $name
  if(!$problem){
   $page=Get-AC8IntegratedModPage $DataRoot $name
   if(!$page){$page=Get-AC8IntegratedModPage $DataRoot ('_'+$name)}
   if($page){$problem="已整合，请在「$page」管理"}
  }
  if(!$problem -and @($items | Where-Object {$_.Name -eq $name}).Count){$problem='同一来源里有重名的 Mod'}
  $existing=$null
  if(!$problem -and $name -and (Test-Path -LiteralPath (Join-Path $mods $name))){$existing='enabled'}elseif(!$problem -and $name -and (Test-Path -LiteralPath (Join-Path $mods ('_'+$name)))){$existing='disabled'}
  $items+=[pscustomobject]@{Name=$name;Kind=$root.Kind;Path=$root.Path;Problem=$problem;Existing=$existing}
 }
 $files=@(Get-ChildItem -LiteralPath $scan -Recurse -File -Force)
 $loader=@($files | Where-Object {Test-AC8ModSkippedFile $_.Name} | ForEach-Object Name | Select-Object -Unique)
 if($loader.Count){$warnings+=('含有 UE4SS 本体文件（'+($loader -join '、')+'），不会安装：本整合包已经自带 UE4SS。')}
 # Only Pak files outside every mod folder are left out (game Paks such as LogicMods or ~mods).
 $roots=@($items | ForEach-Object {$_.Path.TrimEnd('\')+'\'})
 if(@($files | Where-Object {$_.Extension -in @('.pak','.utoc','.ucas')} | Where-Object {$file=$_.FullName;!@($roots | Where-Object {$file.StartsWith($_,[StringComparison]::OrdinalIgnoreCase)}).Count}).Count){$warnings+='含有 .pak 资源文件，不会安装：Pak 由游戏自身加载，需要时请按该 Mod 的说明手动放入游戏目录。'}
 $shared=@(Get-ChildItem -LiteralPath $scan -Recurse -Directory -Force -Filter 'shared' | ForEach-Object {Get-ChildItem -LiteralPath $_.FullName -Directory -Force} | Where-Object {$_.Name -ne 'UEHelpers'} | ForEach-Object Name | Select-Object -Unique)
 if($shared.Count){$warnings+=('含有共享库（'+($shared -join '、')+'），不会安装：本包不会导入独立共享库，请核对该 MOD 的依赖。')}
 if(@($items | Where-Object {!$_.Problem -and $_.Kind -match 'C\+\+'}).Count){$warnings+='C++ Mod 会在游戏中运行原生代码：只安装可信来源的 Mod，并确认它适用于本包的 UE4SS 版本（3.0.1 实验版 e3ba1016），否则可能无法加载或导致崩溃。'}
 return [pscustomobject]@{Source=$source;Staging=$staging;Items=$items;Warnings=$warnings}
 }catch{Remove-AC8ExtraModTree $staging;throw}
}
function Remove-AC8ExtraModTree([string]$Path) {
 # Deletes without following filesystem links (Windows PowerShell 5.1 Remove-Item -Recurse does follow them).
 if(!$Path -or !(Test-Path -LiteralPath $Path)){return}
 $item=Get-Item -LiteralPath $Path -Force
 if($item.Attributes -band [IO.FileAttributes]::ReparsePoint -or !$item.PSIsContainer){if($item.PSIsContainer){[IO.Directory]::Delete($item.FullName,$false)}else{$item.Attributes='Normal';$item.Delete()};return}
 foreach($child in @(Get-ChildItem -LiteralPath $Path -Force)){Remove-AC8ExtraModTree $child.FullName}
 [IO.Directory]::Delete($item.FullName,$false)
}
function Remove-AC8ExtraModPlan($Plan) {if($Plan -and $Plan.Staging){Remove-AC8ExtraModTree $Plan.Staging}}
function Get-AC8ExtraModBackupFolder([string]$DataRoot) {
 $folder=Join-Path (Get-AC8ExtraModDirectory $DataRoot 'ue4ss-mods-removed') ((Get-Date -Format 'yyyyMMdd-HHmmss')+'-'+[guid]::NewGuid().ToString('N'))
 [void][IO.Directory]::CreateDirectory($folder);return $folder
}
function Install-AC8ExtraModPlan($Plan,[string]$DataRoot) {
 $mods=Get-AC8ExtraModDirectory $DataRoot 'ue4ss-mods'
 $work=Join-Path (Get-AC8ExtraModDirectory $DataRoot 'ue4ss-mods-staging') ('copy-'+[guid]::NewGuid().ToString('N'))
 $results=@()
 try{
  foreach($item in $Plan.Items){
   if($item.Problem){$results+=[pscustomobject]@{Name=$item.Name;Message=$item.Problem};continue}
   if($item.Existing){$results+=[pscustomobject]@{Name=$item.Name;Message='已有同名 MOD，已跳过'};continue}
   $copy=Join-Path $work $item.Name
   Copy-AC8ModTree $item.Path $copy
   Assert-AC8Snapshot $copy $item.Files
  }
  foreach($item in $Plan.Items | Where-Object {!$_.Problem -and !$_.Existing}){
   [IO.Directory]::Move((Join-Path $work $item.Name),(Join-Path $mods $item.Name))
   $results+=[pscustomobject]@{Name=$item.Name;Message='已导入'}
  }
 }finally{Remove-AC8ExtraModTree $work}
 return $results
}
function Set-AC8ExtraModEnabled([string]$DataRoot,[string]$Name,[bool]$Enabled) {
 # Enabled: the folder name without leading _; disabled: _ + name (what Get-AC8ExtraMods skips).
 if(!(Test-AC8ExtraModName ($Name -replace '^_',''))){throw '无效的 MOD 名称。'}
 $mods=Get-AC8ExtraModDirectory $DataRoot 'ue4ss-mods';$path=Join-Path $mods $Name
 if(!$Name -or $Name.Contains('\') -or $Name.Contains('/') -or !(Test-Path -LiteralPath $path -PathType Container)){throw "找不到附加 Mod：$Name"}
 Assert-AC8NoLinks $path -Tree
 $plain=$Name.TrimStart('_')
 if($Enabled){
  $problem=Get-AC8ExtraModNameProblem $plain;if($problem){throw ("无法启用 $Name：$problem。请先在文件夹中改名。")}
  $target=$plain
 }else{$target='_'+$plain}
 if($target -ceq $Name){return $Name}
 if(Test-Path -LiteralPath (Join-Path $mods $target)){throw "已有同名文件夹 $target，请先处理重复的 Mod。"}
 [IO.Directory]::Move($path,(Join-Path $mods $target));return $target
}
function Remove-AC8ExtraMod([string]$DataRoot,[string]$Name) {
 # Not deleted: moved to ue4ss-mods-removed\<time>\<name>, where it can be restored by moving it back.
 if(!(Test-AC8ExtraModName ($Name -replace '^_',''))){throw '无效的 MOD 名称。'}
 $mods=Get-AC8ExtraModDirectory $DataRoot 'ue4ss-mods';$path=Join-Path $mods $Name
 if(!$Name -or $Name.Contains('\') -or $Name.Contains('/') -or !(Test-Path -LiteralPath $path -PathType Container)){throw "找不到附加 Mod：$Name"}
 $page=Get-AC8IntegratedModPage $DataRoot $Name
 if($page){throw "这是工作台集成模块，请在「$page」管理。"}
 Assert-AC8NoLinks $path -Tree
 $backup=Get-AC8ExtraModBackupFolder $DataRoot
 [IO.Directory]::Move($path,(Join-Path $backup $Name));return (Join-Path $backup $Name)
}

function Get-AC8OrderedModFolders([string]$Root){
 $folder=Join-Path $Root 'ue4ss-mods'
 if(!(Test-Path -LiteralPath $folder)){return}
 $remaining=@(Get-ChildItem -LiteralPath $folder -Directory -Force | Sort-Object Name)
 $order=Join-Path $Root 'ExtraModOrder.txt'
 if(!(Test-Path -LiteralPath $order)){$remaining;return}
 Assert-AC8NoLinks $order
 foreach($name in [IO.File]::ReadAllLines($order)){
  $remaining | Where-Object {$_.Name.TrimStart('_') -eq $name}
  $remaining=@($remaining | Where-Object {$_.Name.TrimStart('_') -ne $name})
 }
 $remaining
}
function Move-AC8ExtraMod([string]$Root,[string]$Name,[string]$Target,[bool]$Before){
 $all=@(Get-AC8OrderedModFolders $Root | ForEach-Object Name)
 $visible=New-Object 'System.Collections.Generic.List[string]'
 foreach($item in $all){if(!(Get-AC8IntegratedModPage $Root $item)){$visible.Add($item)}}
 if(!$visible.Contains($Name) -or !$visible.Contains($Target)){throw '列表已变化，请刷新后重试。'}
 if($Name -eq $Target){return}
 [void]$visible.Remove($Name)
 $index=$visible.IndexOf($Target)
 if(!$Before){$index++}
 $visible.Insert($index,$Name)
 $j=0
 for($i=0;$i -lt $all.Count;$i++){
  if(!(Get-AC8IntegratedModPage $Root $all[$i])){$all[$i]=$visible[$j];$j++}
 }
 $path=Join-Path $Root 'ExtraModOrder.txt'
 $temp=$path+'.'+[guid]::NewGuid().ToString('N')
 try{
  [IO.File]::WriteAllLines($temp,[string[]]@($all | ForEach-Object {$_.TrimStart('_')}))
  if([IO.File]::Exists($path)){[IO.File]::Replace($temp,$path,[System.Management.Automation.Language.NullString]::Value)}
  else{[IO.File]::Move($temp,$path)}
 }finally{if([IO.File]::Exists($temp)){[IO.File]::Delete($temp)}}
}

function Get-AC8EnabledExtraMods([string]$Root) {
 if(Test-Path -LiteralPath (Join-Path $Root 'multirole-balance.enabled')){
  if(Test-Path -LiteralPath (Join-Path $Root 'ue4ss-mods/SPWeaponCustomizer')){throw '请先停用附加 MOD 中的 SPWeaponCustomizer，避免两套武器菜单同时加载。'}
  $source=Join-Path $Root 'optional-mods/SPWeaponCustomizer'
  [pscustomobject]@{Name='SPWeaponCustomizer';Path=$source;Files=@(Get-AC8Snapshot $source)}
 }
 $folder=Join-Path $Root 'ue4ss-mods'
 if(!(Test-Path -LiteralPath $folder)){return}
 Assert-AC8NoLinks $folder -Tree
 foreach($mod in Get-AC8OrderedModFolders $Root){
  if($mod.Name.StartsWith('_')){continue}
  if(!(Test-AC8ExtraModName $mod.Name) -or !(Get-AC8ModLayoutKind $mod.FullName)){throw "Invalid enabled extra MOD: $($mod.Name)"}
  $files=@(Get-AC8Snapshot $mod.FullName)
  if(@($files | Where-Object {Test-AC8ModSkippedFile ([IO.Path]::GetFileName($_.Path))}).Count){throw "Loader files found in extra MOD: $($mod.Name)"}
  [pscustomobject]@{Name=$mod.Name;Path=$mod.FullName;Files=$files}
 }
}
function Install-AC8ExtraMods($Mods,[string]$Destination) {
 foreach($mod in $Mods){
  $target=Join-Path $Destination $mod.Name
  if(Test-Path -LiteralPath $target){throw "Extra MOD deployment conflict: $($mod.Name)"}
  Copy-AC8ModTree $mod.Path $target
  Assert-AC8Snapshot $target $mod.Files
  Add-Content -LiteralPath (Join-Path $Destination 'mods.txt') -Value ($mod.Name+' : 1') -Encoding ASCII
  Write-Host ('EXTRA MOD: '+$mod.Name)
 }
}

function Invoke-AC8HudAction($Request,[string]$Root) {
 $name='AC8EnhancedHUD'
 $library=Get-AC8ExtraModDirectory $Root 'ue4ss-mods'
 $enabled=Join-Path $library $name
 $disabled=Join-Path $library ('_'+$name)
 $template=Join-Path $Root 'optional-mods\AC8EnhancedHUD'
 $existing=if(Test-Path -LiteralPath $enabled){$enabled}elseif(Test-Path -LiteralPath $disabled){$disabled}
 if((Test-Path -LiteralPath $enabled) -and (Test-Path -LiteralPath $disabled)){throw '发现两份增强 HUD。请保留所需副本后重试。'}
 $source=if($existing){$existing}else{$template}
 Assert-AC8NoLinks $source -Tree
 if(!(Get-AC8ModLayoutKind $source)){throw '增强 HUD 模块不完整。'}
 $config=Join-Path $source 'config.ini'
 $stage=$null
 try{
  if(!$existing){
   $stage=Join-Path (Get-AC8ExtraModDirectory $Root 'ue4ss-mods-staging') ([guid]::NewGuid().ToString('N'))
   Copy-AC8ModTree $source $stage
   Assert-AC8Snapshot $stage @(Get-AC8Snapshot $source)
   $config=Join-Path $stage 'config.ini'
  }
  if($Request.Action -eq 'HudSave'){
   if((Get-AC8FileHash -LiteralPath $config).Hash -ne $Request.ExtraToken){throw '增强 HUD 配置已改变，请重新打开设置。'}
   $temp=$config+'.'+[guid]::NewGuid().ToString('N')
   try{
    [IO.File]::WriteAllText($temp,[string]$Request.HudConfig,[Text.UTF8Encoding]::new($false))
    [IO.File]::Replace($temp,$config,($temp+'.old'))
   }finally{[IO.File]::Delete($temp);[IO.File]::Delete($temp+'.old')}
  }
  if($stage){
   $destination=if($Request.Action -eq 'HudEnable'){$enabled}else{$disabled}
   [IO.Directory]::Move($stage,$destination)
  }elseif($Request.Action -eq 'HudEnable' -and $existing -eq $disabled){
   [IO.Directory]::Move($disabled,$enabled)
  }elseif($Request.Action -eq 'HudDisable' -and $existing -eq $enabled){
   [IO.Directory]::Move($enabled,$disabled)
  }
 }finally{if($stage){Remove-AC8ExtraModTree $stage}}
 return [pscustomobject]@{Success=$true;Title='增强 HUD';Message='增强 HUD 设置已保存，下次启动游戏生效。'}
}

function Invoke-AC8ExtraModAction($Request,[string]$Root) {
 $lock=Enter-AC8Operation $Root
 try{
  if($Request.Action -ne 'ExtraList' -and (Test-Path -LiteralPath (Join-Path $Root 'active-session.json'))){
   throw '请先结束当前会话并完成恢复，再管理附加 MOD。'
  }
  if($Request.Action -in @('HudSave','HudEnable','HudDisable')){return Invoke-AC8HudAction $Request $Root}
  if($Request.Action -in @('BalanceEnable','BalanceDisable')){
   $flag=Join-Path $Root 'multirole-balance.enabled'
   if($Request.Action -eq 'BalanceEnable'){
    if(Test-Path -LiteralPath (Join-Path $Root 'ue4ss-mods/SPWeaponCustomizer')){throw '请先停用附加 MOD 中的 SPWeaponCustomizer。'}
    if(!(Test-Path -LiteralPath $flag)){[IO.File]::Open($flag,'CreateNew','Write','None').Dispose()}
   }elseif(Test-Path -LiteralPath $flag){Assert-AC8NoLinks $flag;[IO.File]::Delete($flag)}
   return [pscustomobject]@{Success=$true;Message='机体加强设置已保存，下次启动游戏生效。'}
  }
  $message='选择要启停或移除的 MOD。'
  if($Request.Action -in @('ExtraPreview','ExtraImport')){
   $plan=New-AC8ExtraModPlan $Root ([string]$Request.ExtraPath)
   try{
    $entries=@()
    $lines=@()
    foreach($item in $plan.Items){
     if($item.Problem){$lines+= "$($item.Name) 无法导入：$($item.Problem)";continue}
     $files=@(Get-AC8Snapshot $item.Path | Where-Object {!(Test-AC8ModSkippedFile ([IO.Path]::GetFileName($_.Path)))})
     $item | Add-Member -NotePropertyName Files -NotePropertyValue $files
     $resources=@($files | Where-Object {$_.Path -match '\.(pak|utoc|ucas)$'})
     $line="$($item.Name) ($($item.Kind))，共 $($files.Count) 个文件"
     if($resources.Count){
      $line+="，$($resources.Count) 个资源文件：" + (($resources | Select-Object -First 8 | ForEach-Object Path) -join '、')
     }
     if($item.Existing){$line+='，已有同名 MOD，将跳过'}
     $lines+=$line
     $entries+=[pscustomobject]@{Name=$item.Name;Existing=$item.Existing;Files=$files}
    }
    $fingerprint=ConvertTo-Json -InputObject $entries -Depth 8 -Compress
    $sha=[Security.Cryptography.SHA256]::Create()
    try{$token=[Convert]::ToBase64String($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($fingerprint)))}finally{$sha.Dispose()}
    if($Request.Action -eq 'ExtraPreview'){
     $addable=@($entries | Where-Object {!$_.Existing}).Count
     $message=(@($lines)+@($plan.Warnings)) -join [Environment]::NewLine
     if(!$message){$message='没有找到 UE4SS MOD。需要 Scripts/main.lua 或 dlls/main.dll。'}
     return [pscustomobject]@{Success=($addable -gt 0);Title='附加 MOD 导入预览';Message=$message;ExtraToken=$token}
    }
    if($Request.ExtraToken -cne $token){throw '来源或已有 MOD 在预览后发生变化，请重新预览。'}
    $results=@(Install-AC8ExtraModPlan $plan $Root)
    $message=($results | ForEach-Object {"$($_.Name) $($_.Message)"}) -join [Environment]::NewLine
   }finally{Remove-AC8ExtraModPlan $plan}
  }elseif($Request.Action -in @('ExtraEnable','ExtraDisable')){
   $null=Set-AC8ExtraModEnabled $Root ([string]$Request.ExtraName) ($Request.Action -eq 'ExtraEnable')
   $message='已保存启停状态，下次启动游戏生效。'
  }elseif($Request.Action -in @('ExtraBefore','ExtraAfter')){
   Move-AC8ExtraMod $Root ([string]$Request.ExtraName) ([string]$Request.ExtraPath) ($Request.Action -eq 'ExtraBefore')
   $message='顺序已保存，下次启动时从上到下加载。'
  }elseif($Request.Action -eq 'ExtraRemove'){
   $backup=Remove-AC8ExtraMod $Root ([string]$Request.ExtraName)
   $message="已移到可恢复目录：$backup"
  }
  $folder=Join-Path $Root 'ue4ss-mods'
  $mods=@()
  if(Test-Path -LiteralPath $folder){
   Assert-AC8NoLinks $folder
   $mods=@(Get-AC8OrderedModFolders $Root | Where-Object {!(Get-AC8IntegratedModPage $Root $_.Name)} | ForEach-Object {
    [pscustomobject]@{Name=$_.Name;Enabled=(!$_.Name.StartsWith('_'))}
   })
  }
  [pscustomobject]@{Success=$true;Title='附加 MOD';Message=$message;ExtraMods=$mods}
 }finally{Exit-AC8Operation $lock}
}
