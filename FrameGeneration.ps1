# DLSS Frame Generation only. Called by the MOD session before starting the game.
function Read-AC8FrameGeneration([string]$Path) {
 $allowed=@('r.Streamline.InitializePlugin','r.Streamline.DLSSG.Enable');$values=@{};$section=''
 foreach($line in [IO.File]::ReadAllLines($Path)){
  $clean=$line.Trim();if(!$clean -or $clean.StartsWith(';') -or $clean.StartsWith('#')){continue}
  if($clean -match '^\[([^\]]+)\]$'){
   $section=$Matches[1];if($section -ne 'ConsoleVariables'){throw 'FrameGeneration.ini supports only [ConsoleVariables].'};continue
  }
  if($section -ne 'ConsoleVariables' -or $clean -notmatch '^([^=]+?)\s*=\s*([01])$'){throw 'Invalid frame generation setting.'}
  $name=$Matches[1].Trim();$value=$Matches[2]
  if($name -notin $allowed -or $values.ContainsKey($name)){throw 'FrameGeneration.ini contains an unsupported or duplicate setting.'}
  $values[$name]=$value
 }
 if($values.Count -ne 2){throw 'FrameGeneration.ini requires the two Streamline frame generation settings.'}
 return $values
}
function Merge-AC8FrameGeneration([string]$Text,$Values) {
 $lines=New-Object 'Collections.Generic.List[string]'
 foreach($line in [regex]::Split($Text,'(?<=\n)')){$lines.Add($line)}
 $newline=if($Text.Contains("`r`n")){"`r`n"}elseif($Text.Contains("`n")){"`n"}else{"`r`n"}
 $section='';$seen=@{};$lastEnd=-1
 for($i=0;$i -lt $lines.Count;$i++){
  $line=$lines[$i]
  if($line -match '^[\t ]*\[([^\]]+)\]'){
   if($section -eq 'ConsoleVariables'){$lastEnd=$i}
   $section=$Matches[1];continue
  }
  if($section -ne 'ConsoleVariables'){continue}
  if($line -match '^(?<prefix>[\t ]*(?<key>r\.Streamline\.(?:InitializePlugin|DLSSG\.Enable))[\t ]*=[\t ]*)(?<value>[^;#\r\n]*)(?<comment>[;#][^\r\n]*)?(?<eol>\r?\n|\r)?$'){
   $name=$Matches['key'];$prefix=$Matches['prefix'];$comment=$Matches['comment'];$eol=$Matches['eol']
   $trailing=[regex]::Match($Matches['value'],'[\t ]*$').Value
   $lines[$i]=$prefix+$Values[$name]+$trailing+$comment+$eol;$seen[$name]=$true
  }
 }
 if($section -eq 'ConsoleVariables'){$lastEnd=$lines.Count}
 $missing=@('r.Streamline.InitializePlugin','r.Streamline.DLSSG.Enable' | Where-Object {!$seen.ContainsKey($_)})
 if($missing.Count){
  if($lastEnd -lt 0){
   $lastEnd=$lines.Count
   if($lastEnd -gt 0 -and $lines[$lastEnd-1] -and !$lines[$lastEnd-1].EndsWith("`n")){$lines[$lastEnd-1]+=$newline}
   $lines.Add('[ConsoleVariables]'+$newline);$lastEnd=$lines.Count
  }
  if($lastEnd -gt 0 -and $lines[$lastEnd-1] -and !$lines[$lastEnd-1].EndsWith("`n")){$lines[$lastEnd-1]+=$newline}
  $block=($missing | ForEach-Object {$_+'='+$Values[$_]+$newline}) -join ''
  $lines.Insert($lastEnd,$block)
 }
 return ($lines -join '')
}
function Get-AC8FrameGenerationHash([byte[]]$Bytes) {
 $hash=[Security.Cryptography.SHA256]::Create()
 try{return [BitConverter]::ToString($hash.ComputeHash($Bytes)).Replace('-','')}finally{$hash.Dispose()}
}
function Apply-AC8FrameGeneration {
 param([string]$PackageRoot,[string]$BackupRoot,[string]$LocalAppData=$env:LOCALAPPDATA)
 $values=Read-AC8FrameGeneration (Join-Path $PackageRoot 'FrameGeneration.ini')
 if([string]::IsNullOrWhiteSpace($LocalAppData)){throw 'Cannot locate the current user LocalAppData folder.'}
 $local=[IO.Path]::GetFullPath($LocalAppData).TrimEnd('\','/')
 $target=[IO.Path]::GetFullPath((Join-Path $local 'BANDAI NAMCO Entertainment/ACE COMBAT 8/Saved/Config/Windows/Engine.ini'))
 if(!$target.StartsWith($local+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'Engine.ini target escaped LocalAppData.'}
 $exists=[IO.File]::Exists($target);[byte[]]$before=@();$attributes=[IO.FileAttributes]::Normal
 $encoding=[Text.UTF8Encoding]::new($false,$true);$preamble=[byte[]]@();$text=''
 if($exists){
  $before=[IO.File]::ReadAllBytes($target);$attributes=[IO.File]::GetAttributes($target);$skip=0
  if($before.Length -ge 3 -and $before[0] -eq 239 -and $before[1] -eq 187 -and $before[2] -eq 191){$preamble=[byte[]]@(239,187,191);$skip=3}
  elseif($before.Length -ge 2 -and $before[0] -eq 255 -and $before[1] -eq 254){$encoding=[Text.UnicodeEncoding]::new($false,$false,$true);$preamble=[byte[]]@(255,254);$skip=2}
  elseif($before.Length -ge 2 -and $before[0] -eq 254 -and $before[1] -eq 255){$encoding=[Text.UnicodeEncoding]::new($true,$false,$true);$preamble=[byte[]]@(254,255);$skip=2}
  try{$text=$encoding.GetString($before,$skip,$before.Length-$skip)}catch{
   if($skip){throw};$encoding=[Text.Encoding]::Default;$text=$encoding.GetString($before)
  }
 }
 $merged=Merge-AC8FrameGeneration $text $values
 [byte[]]$after=@($preamble)+@($encoding.GetBytes($merged))
 $changed=!(Get-AC8FrameGenerationHash $before).Equals((Get-AC8FrameGenerationHash $after))
 $wasReadOnly=($attributes -band [IO.FileAttributes]::ReadOnly) -ne 0
 if(!$changed -and $wasReadOnly){return [pscustomobject]@{Path=$target;Changed=$false;Backup=$null}}
 # Keep the original bytes and attributes before any configuration/attribute write.
 $backup=Join-Path $BackupRoot ('frame-generation-'+[guid]::NewGuid().ToString('N'))
 New-Item -ItemType Directory -Path $backup -Force | Out-Null
 if($exists){[IO.File]::WriteAllBytes((Join-Path $backup 'Engine.ini'),$before)}
 $record=[ordered]@{Target=$target;Existed=$exists;OriginalAttributes=[int]$attributes;OriginalSHA256=(Get-AC8FrameGenerationHash $before);AppliedSHA256=(Get-AC8FrameGenerationHash $after)}
 [IO.File]::WriteAllText((Join-Path $backup 'backup.json'),($record | ConvertTo-Json),[Text.UTF8Encoding]::new($false))
 New-Item -ItemType Directory -Path ([IO.Path]::GetDirectoryName($target)) -Force | Out-Null
 $temporary=$target+'.ac8-fg-'+[guid]::NewGuid().ToString('N')+'.tmp';$replaced=$false
 try {
  [IO.File]::WriteAllBytes($temporary,$after)
  if($exists){
   if((Get-AC8FrameGenerationHash ([IO.File]::ReadAllBytes($target))) -ne $record.OriginalSHA256){throw 'Engine.ini changed concurrently; no frame generation settings applied.'}
   [IO.File]::SetAttributes($target,($attributes -band (-bnot [IO.FileAttributes]::ReadOnly)))
   [IO.File]::Replace($temporary,$target,[System.Management.Automation.Language.NullString]::Value)
  }else{[IO.File]::Move($temporary,$target)}
  $replaced=$true
  # Keep the game from overwriting these startup console variables.
  [IO.File]::SetAttributes($target,($attributes -bor [IO.FileAttributes]::ReadOnly))
 }catch{
  # Existing configuration is restored if replacement or attribute application fails.
  if($exists){
   if($replaced){[IO.File]::WriteAllBytes($target,$before)}
   if([IO.File]::Exists($target)){[IO.File]::SetAttributes($target,$attributes)}
  }
  throw
 }finally{if([IO.File]::Exists($temporary)){[IO.File]::Delete($temporary)}}
 return [pscustomobject]@{Path=$target;Changed=$true;Backup=$backup}
}
