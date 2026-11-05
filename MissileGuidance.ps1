function Read-AC8MissileGuidance([string]$Path) {
 $defaults=[ordered]@{MSL=1.0;QAAM=1.0;SAAM=0.95;'2AAM'=0.95;'4AAM'=0.9;'6AAM'=0.9;HCAA=0.8;HPAA=0.75;HVAA=0.85;LAAM=0.9;SASM=0.9;STORY=1.0;EASY=1.0}
 if(!(Test-Path -LiteralPath $Path -PathType Leaf)){return $defaults}
 $values=[ordered]@{}
 foreach($raw in [IO.File]::ReadAllLines($Path)){
  $line=$raw.Trim().TrimStart([char]0xFEFF)
  if(!$line -or $line.StartsWith(';') -or $line.StartsWith('#')){continue}
  if($line -cnotmatch '^([A-Z0-9]+)\s*=\s*([0-9]+(?:\.[0-9]{1,3})?)$'){throw "Invalid missile guidance setting: $line"}
  $key=$Matches[1];$number=$Matches[2]
  if(!$defaults.Contains($key) -or $values.Contains($key)){throw "Unknown or duplicate missile guidance key: $key"}
  $value=[double]::Parse($number,[Globalization.CultureInfo]::InvariantCulture)
  if([double]::IsNaN($value) -or [double]::IsInfinity($value) -or $value -lt 0 -or $value -gt 1){throw "Missile guidance $key must be between 0 and 1."}
  $values[$key]=$value
 }
 if($values.Count -ne 13){throw 'MissileGuidance.ini must contain all 13 values.'}
 return $values
}
function Write-AC8PropNavSettings($Values,[string]$Path) {
 $lines=@('; Generated from FPMCI settings; applied on next launch.','[player]')
 foreach($key in @('MSL','QAAM','SAAM','2AAM','4AAM','6AAM','HCAA','HPAA','HVAA','LAAM','SASM')){
  $lines+=@(($key.ToLowerInvariant()+' = {'),(' HomingForesightAmount = '+$Values[$key].ToString('0.000',[Globalization.CultureInfo]::InvariantCulture)),' LockonRange =',' MaxRotationAngle =',' MaxHomingAngle =',' LifeTime =','}')
 }
 # No enemy section: retain FPMCI's existing enemy behavior, per upstream docs.
 [IO.File]::WriteAllLines($Path,$lines,[Text.Encoding]::ASCII)
}
function Write-AC8MissileGuidance($Values,[string]$Path) {
 $lines=@('-- Generated from MissileGuidance.ini at MOD startup.','return {')
 foreach($key in $Values.Keys){$lines+=' ["'+$key+'"]='+$Values[$key].ToString('0.000',[Globalization.CultureInfo]::InvariantCulture)+','}
 $lines+='}'
 [IO.File]::WriteAllLines($Path,$lines,[Text.Encoding]::ASCII)
}


function Read-AC8FuseSettings([string]$Path) {
 $values=[ordered]@{};$limits=@{}
 foreach($key in @('MSL','QAAM','SAAM','2AAM','4AAM','6AAM','HCAA','HPAA','HVAA','LAAM','SASM')){
  $values[$key]=0;$limits[$key]=@(0,1)
  foreach($spec in @(@('TRIGGER',30,200),@('BLAST',50,500),@('DAMAGE',30,500))){$name=$key+'_'+$spec[0];$values[$name]=[double]$spec[1];$limits[$name]=@(1,$spec[2])}
 }
 if(!(Test-Path -LiteralPath $Path)){return $values}
 $seen=@{}
 foreach($raw in [IO.File]::ReadAllLines($Path)){
  $line=$raw.Trim().TrimStart([char]0xFEFF)
  if(!$line -or $line.StartsWith(';') -or $line.StartsWith('#')){continue}
  if($line -cnotmatch '^([A-Z0-9_]+)\s*=\s*([0-9]+(?:\.[0-9]{1,3})?)$'){throw 'Invalid proximity fuse setting.'}
  $key=$Matches[1];$value=[double]::Parse($Matches[2],[Globalization.CultureInfo]::InvariantCulture)
  if(!$values.Contains($key) -or $seen.ContainsKey($key)){throw 'Unknown or duplicate fuse setting.'}
  $range=$limits[$key]
  if($value -lt $range[0] -or $value -gt $range[1] -or ($range[0] -eq 0 -and $value -notin @(0,1))){throw 'Fuse setting outside allowed range.'}
  $seen[$key]=$true;$values[$key]=$value
 }
 foreach($key in $values.Keys | Where-Object {$_ -notmatch '_'}){if(!$seen.ContainsKey($key)){throw 'Fuse settings require all 11 missile switches.'}}
 return $values
}
function Write-AC8FuseSettings($Values,[string]$Path) {
 $lines=@('-- Generated from FPMCI; next launch only.','return {')
 foreach($key in $Values.Keys | Where-Object {$_ -notmatch '_'}){
  $active=if($Values[$key]){'true'}else{'false'}
  $line=' ["'+$key.ToLowerInvariant()+'"]={enabled='+$active
  foreach($spec in @(@('TRIGGER','trigger'),@('BLAST','blast'),@('DAMAGE','damage'))){$line+=','+$spec[1]+'='+$Values[$key+'_'+$spec[0]].ToString('0.###',[Globalization.CultureInfo]::InvariantCulture)}
  $lines+=$line+'},'
 }
 $lines+='}'
 [IO.File]::WriteAllLines($Path,$lines,[Text.Encoding]::ASCII)
}
